--!nocheck
-- QA r3 (fixer r3-ui-1) : lisibilité et placement sur téléphone et console.
--   * suivi de quête : titre assez large pour chaque quête d'accueil et l'objectif Supernova à 18 px
--     de référence (GDD §10.1), largeur estimée à 0,55 em par caractère, plancher MinTextSize 18
local roblox = require("@lune/roblox")
local Layout = require("../harness/Layout")
local Gamepad = require("../harness/Gamepad")

local Vector2 = roblox.Vector2

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000
	local MIN_TEXT = 18 -- px de référence (GDD §10.1)
	local EM = 0.55 -- largeur moyenne d'un caractère FredokaOne, en em (estimation prudente)

	-- largeur estimée d'un texte d'une ligne à `size` px
	local function textWidth(text, size)
		return (utf8.len(text) or #text) * EM * size
	end

	-- schéma chargé une fois, AVANT les harnais clients (Harness.new redirige les journaux réseau)
	local Schema = Harness.new():require("ServerScriptService.Server.Data.Schema")

	-- =============================================================================================
	-- Suivi de quête : titre lisible (≥ 18 px) pour chaque quête et l'objectif Supernova
	-- =============================================================================================
	local function hudSetup(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", touch = opts.touch })
		h.localPlayer.LocaleId = opts.locale or "en-us"
		h:createRemotes()
		if opts.viewport then
			h.workspace.CurrentCamera.ViewportSize = opts.viewport
		end
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = {
			h = h,
			Clock = Clock,
			Root = h:require(CLIENT .. "UI.Root"),
			State = h:require(CLIENT .. "Controllers.StateController"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			WSC = h:require(CLIENT .. "Controllers.WorldStateController"),
			VFX = h:require(CLIENT .. "Controllers.VFXController"),
			Panels = h:require(CLIENT .. "Controllers.PanelController"),
			FX = h:require(CLIENT .. "UI.ScreenFX"),
			Input = h:require(CLIENT .. "Controllers.InputController"),
			HUD = h:require(CLIENT .. "UI.HUD"),
			Formulas = h:require("ReplicatedStorage.Shared.Logic.Formulas"),
			Quests = h:require("ReplicatedStorage.Shared.Config.Quests"),
			vfx = {},
			open = nil,
		}
		c.VFX.playDash = function() end
		c.VFX.playUpgrade = function(track, level)
			table.insert(c.vfx, { track = track, level = level })
		end
		c.WSC.localSlot = function()
			return 1
		end
		c.WSC.lineLength = function()
			return 0
		end
		c.Panels.current = function()
			return c.open
		end
		c.Root.Init()
		c.State.Init()
		c.Prefs.Init()
		c.Prefs.Start()
		c.FX.Init()
		c.Input.Init()
		c.HUD.Init()
		c.FX.Start()
		c.Input.Start()
		c.HUD.Start()
		return c
	end

	local function snapshot(c, data)
		local profile = Schema.defaults()
		for k, v in data or {} do
			profile[k] = v
		end
		c.h:fireClient(REMOTES .. "DataSnapshot", profile)
		c.h:settle(1)
	end

	local function patch(c, values)
		c.h:fireClient(REMOTES .. "DataPatch", values, {})
		c.h:settle(1)
	end

	local function frames(c, n, dt)
		for _ = 1, n or 3 do
			c.Clock.advance(dt or 1 / 30)
			c.h:step(dt or 1 / 30, 1)
		end
		c.h:settle(1)
	end

	local function hud(c)
		return c.h.localPlayer.PlayerGui.HUD.Safe
	end

	describe("Fix r3 ui-1 › suivi de quête : titre lisible à 18 px", function()
		for _, lang in { "en-us", "fr-fr" } do
			it(`{lang} : chaque quête d'accueil et chaque Supernova tiennent sur la largeur`, function()
				local c = hudSetup({ locale = lang, touch = true, viewport = Vector2.new(844, 390) })
				snapshot(c, { onboarding = { step = 1, p = 0 } })
				c.HUD.reveal("questTracker", false)
				frames(c, 3)
				local pill = hud(c).QuestTracker.Pill
				local title = pill.Title
				-- plancher de lisibilité : TextScaled ne descend jamais sous 18 px de référence
				local constraint = title:FindFirstChildOfClass("UITextSizeConstraint")
				expect(constraint.MinTextSize >= MIN_TEXT).toBe(true)
				expect(constraint.MaxTextSize >= MIN_TEXT).toBe(true)
				Layout.apply(c.h)
				local r = Layout.rect(title)
				local width, height = r.w / r.k, r.h / r.k
				expect(height >= MIN_TEXT).toBe(true)
				local bad = {}
				local function check(label)
					if textWidth(title.Text, MIN_TEXT) > width + 1e-6 then
						table.insert(
							bad,
							`{label} « {title.Text} » ({math.floor(textWidth(title.Text, MIN_TEXT))} > {width})`
						)
					end
				end
				for step = 1, #c.Quests.Onboarding do
					patch(c, { onboarding = { step = step, p = 0 } })
					frames(c, 7)
					check("Q" .. step)
				end
				-- objectif long : chaque coût de Supernova, de R0 à bien au-delà de la table
				for r0 = 0, 24 do
					patch(c, { onboarding = { step = #c.Quests.Onboarding + 1, p = 0 }, supernovas = r0 })
					frames(c, 7)
					check("R" .. r0)
				end
				expect(table.concat(bad, "\n")).toBe("")
				-- le titre ne passe ni sous l'icône ni sous le bouton de repli
				Layout.apply(c.h)
				local t, icon, toggle = Layout.rect(title), Layout.rect(pill.Icon), Layout.rect(pill.Toggle)
				local function overlap(a, b)
					return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
				end
				expect(overlap(t, icon)).toBe(false)
				expect(overlap(t, toggle)).toBe(false)
				-- tout reste dans la pastille
				local p = Layout.rect(pill)
				for _, part in { t, icon, toggle, Layout.rect(pill.Bar) } do
					expect(part.x >= p.x - 1e-6 and part.x + part.w <= p.x + p.w + 1e-6).toBe(true)
					expect(part.y >= p.y - 1e-6 and part.y + part.h <= p.y + p.h + 1e-6).toBe(true)
				end
			end)
		end

		it("objectif Supernova : nombre complet s'il tient, abrégé sinon (400,000 puis 10M)", function()
			local c = hudSetup()
			snapshot(c, { onboarding = { step = 8, p = 0 }, supernovas = 0 })
			c.HUD.reveal("questTracker", false)
			frames(c, 7)
			local title = hud(c).QuestTracker.Pill.Title
			expect(title.Text).toBe("Supernova · 400,000")
			patch(c, { supernovas = 1 })
			frames(c, 7)
			expect(title.Text).toBe("Supernova · 10M")
		end)
	end)
	-- =============================================================================================
	-- Améliorer (Q7 « Atteins 10 perchoirs ») : la carte de quête est visible à l'ouverture
	-- =============================================================================================
	local function profile(over)
		local p = Schema.defaults()
		p.lastSettle = T0
		p.lastOnline = T0
		p.settings.lang = "en"
		for k, v in over or {} do
			p[k] = v
		end
		return p
	end

	local function panelSetup(viewport, over, opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", touch = opts.touch, console = opts.console })
		h.localPlayer.LocaleId = "en-us"
		h:createRemotes()
		if viewport then
			h.workspace.CurrentCamera.ViewportSize = viewport
		end
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = {
			h = h,
			Clock = Clock,
			Root = h:require(CLIENT .. "UI.Root"),
			State = h:require(CLIENT .. "Controllers.StateController"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			WSC = h:require(CLIENT .. "Controllers.WorldStateController"),
			ScreenFX = h:require(CLIENT .. "UI.ScreenFX"),
			PC = h:require(CLIENT .. "Controllers.PanelController"),
			Formulas = h:require("ReplicatedStorage.Shared.Logic.Formulas"),
			Balance = h:require("ReplicatedStorage.Shared.Config.Balance"),
		}
		c.Root.Init()
		c.State.Init()
		c.Prefs.Init()
		c.WSC.Init()
		c.State.Start()
		c.Prefs.Start()
		c.WSC.Start()
		c.PC.Init()
		c.PC.Start()
		h:fireClient(REMOTES .. "DataSnapshot", profile(over))
		h:settle(1)
		return c
	end

	-- part visible (0-1) d'un rectangle dans un autre
	local function visibleShare(r, clip)
		local w = math.max(0, math.min(r.x + r.w, clip.x + clip.w) - math.max(r.x, clip.x))
		local hgt = math.max(0, math.min(r.y + r.h, clip.y + clip.h) - math.max(r.y, clip.y))
		return (w * hgt) / math.max(r.w * r.h, 1e-6)
	end

	describe("Fix r3 ui-1 › Améliorer : carte de la quête d'accueil visible à l'ouverture", function()
		local SCREENS = {
			Vector2.new(844, 390),
			Vector2.new(800, 360),
			Vector2.new(667, 375),
			Vector2.new(1280, 720),
		}
		for _, size in SCREENS do
			it(
				`{size.X} × {size.Y} : Q7, la carte Perchoirs (contour doré) est entièrement visible`,
				function()
					local c = panelSetup(size, {
						onboarding = { step = 7, p = 3 },
						glow = 1000000,
					}, { touch = size.X < 1000 })
					c.PC.open("Upgrades")
					c.h:settle(2)
					local Upgrades = c.h:require(CLIENT .. "UI.Panels.Upgrades")
					expect(Upgrades._quest()).toBe("perches")
					local body = c.PC.page("Upgrades").Body
					Layout.apply(c.h)
					local list = Layout.rect(body.List)
					local card = Layout.rect(body.List.Card_perches)
					expect(visibleShare(card, list) > 0.99).toBe(true)
					-- et c'est bien la carte marquée (contour doré) qui pulse
					expect(Upgrades._pulsing()).toBe("perches")
					-- quête finie (10 perchoirs) : l'ordre du GDD revient (Perchoirs en 4e)
					c.h:fireClient(REMOTES .. "DataPatch", { onboarding = { step = 8, p = 0 } }, {})
					c.h:settle(1)
					c.Clock.advance(1)
					c.h:step(0.3, 2)
					expect(Upgrades._quest()).toBeNil()
					local order = {}
					for i, track in c.Balance.UpgradeOrder do
						order[i] = body.List["Card_" .. track].LayoutOrder
					end
					for i = 2, #order do
						expect(order[i] > order[i - 1]).toBe(true)
					end
				end
			)
		end

		it("Q5 visible ; panneau ouvert quand Q7 commence : la liste remonte sur Perchoirs", function()
			local c = panelSetup(Vector2.new(844, 390), {
				onboarding = { step = 5, p = 0 },
				glow = 1000000,
			}, { touch = true })
			c.PC.open("Upgrades")
			c.h:settle(2)
			local body = c.PC.page("Upgrades").Body
			Layout.apply(c.h)
			expect(visibleShare(Layout.rect(body.List.Card_stride), Layout.rect(body.List)) > 0.99).toBe(true)
			-- le joueur a fait défiler la liste ; la quête suivante (Q7) commence panneau ouvert
			body.List.CanvasPosition = Vector2.new(0, 240)
			c.h:fireClient(REMOTES .. "DataPatch", { onboarding = { step = 7, p = 3 } }, {})
			c.h:settle(1)
			expect(body.List.CanvasPosition).toEqual(Vector2.zero)
			Layout.apply(c.h)
			expect(visibleShare(Layout.rect(body.List.Card_perches), Layout.rect(body.List)) > 0.99).toBe(
				true
			)
		end)
	end)
	-- =============================================================================================
	-- Carte d'invitation d'équipage (console, client complet) : jamais sur une fenêtre ouverte ;
	-- repère △ tant qu'Accepter n'est pas sélectionné, ✕ ensuite (docs/07 §6.7)
	-- =============================================================================================
	local K = roblox.Enum.KeyCode

	local function consoleBoot()
		local h = Harness.new({ mode = "client", console = true })
		h.localPlayer.LocaleId = "en-us"
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		-- passe à vendre (id réel) : la Boutique sélectionne son bouton Acheter par défaut
		local Monetization = h:require("ReplicatedStorage.Shared.Config.Monetization")
		Monetization.Passes.VIPStar.id = 777001
		h:boot()
		h:fireClient(
			REMOTES .. "DataSnapshot",
			profile({
				glow = 500000,
				onboarding = { step = 8, p = 0 },
				settings = (function()
					local st = Schema.defaults().settings
					st.lang = "en"
					st.refuseInvites = false
					return st
				end)(),
			})
		)
		h:step(1 / 60, 30)
		h:settle(3)
		local c = {
			h = h,
			Clock = Clock,
			PC = h:require(CLIENT .. "Controllers.PanelController"),
			Crew = nil,
		}
		return c
	end

	local function cframes(c, n)
		for _ = 1, n or 3 do
			c.Clock.advance(1 / 30)
			c.h:step(1 / 30, 1)
		end
		c.h:settle(1)
	end

	local function intersects(a, b)
		return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
	end

	local function sentCount(c, remote)
		local out = {}
		for _, e in c.h.log.serverEvents do
			if e.remote == remote then
				table.insert(out, e.args)
			end
		end
		return out
	end

	describe("Fix r3 ui-1 › carte d'invitation d'équipage", function()
		it("panneau ouvert : la carte attend sa fermeture (jamais sur la fenêtre ni sur Acheter)", function()
			local c = consoleBoot()
			c.h:addPlayer({ userId = 2, name = "Mira" })
			c.h:addPlayer({ userId = 3, name = "Noah" })
			c.h:settle(2)
			c.h.game.GuiService.SelectedObject = nil
			c.PC.open("Shop", { tab = "passes" })
			cframes(c, 8)
			c.h:fireClient(REMOTES .. "CrewInvitePrompt", { inviterId = 2, expiresAt = T0 + 20 })
			cframes(c, 4)
			local Crew = c.h:require(CLIENT .. "UI.Panels.Crew")
			local safe = c.h.localPlayer.PlayerGui.Panels.Safe
			local window = safe.Window
			local card = safe.CrewInvite
			Layout.apply(c.h)
			local selected = Gamepad.selected(c.h)
			expect(selected ~= nil and selected.Name == "Buy").toBe(true)
			-- la carte ne recouvre ni la fenêtre ni le bouton Acheter sélectionné
			local covering = Layout.visible(card) and intersects(Layout.rect(card), Layout.rect(window))
			expect(covering).toBe(false)
			expect(Layout.visible(card) and intersects(Layout.rect(card), Layout.rect(selected))).toBe(false)
			-- en attente : pastille « ! » d'Équipage, △ ne vise pas une carte cachée
			expect(Crew.hasAction()).toBe(true)
			expect(c.PC.focusTarget()).toBeNil()
			-- fermeture : la carte arrive, échéance d'origine conservée (le temps a couru)
			c.PC.close()
			cframes(c, 8)
			expect(card.Visible).toBe(true)
			expect(Crew._shown().inviterId).toBe(2)
			expect(Crew._shown().expiresAt).toBe(T0 + 20)
			expect(c.PC.focusTarget()).toBe(card.Accept)
			-- carte affichée puis panneau ouvert : elle se range, puis revient à la fermeture
			c.PC.open("Upgrades")
			cframes(c, 8)
			expect(card.Visible).toBe(false)
			expect(Crew._shown()).toBeNil()
			expect(#Crew._pending()).toBe(1)
			-- changement de panneau (Améliorer → Supernova) : toujours rangée
			c.PC.open("Supernova")
			cframes(c, 8)
			expect(card.Visible).toBe(false)
			c.PC.close()
			cframes(c, 8)
			expect(card.Visible).toBe(true)
			expect(Crew._shown().inviterId).toBe(2)
			-- invitation expirée pendant qu'un panneau est ouvert : rien ne revient, plus de pastille
			c.PC.open("Shop")
			cframes(c, 4)
			c.Clock.advance(25)
			cframes(c, 2)
			expect(Crew.hasAction()).toBe(false)
			c.PC.close()
			cframes(c, 8)
			expect(card.Visible).toBe(false)
			expect(Crew._shown()).toBeNil()
			expect(#sentCount(c, "CrewRespond")).toBe(0)
			expect(table.concat(c.h.errors, "\n")).toBe("")
		end)

		it("repère △ tant qu'Accepter n'est pas sélectionné, ✕ une fois sélectionné", function()
			local c = consoleBoot()
			c.h:addPlayer({ userId = 2, name = "Mira" })
			c.h:settle(2)
			c.h.game.GuiService.SelectedObject = nil
			c.h:fireClient(REMOTES .. "CrewInvitePrompt", { inviterId = 2, expiresAt = T0 + 20 })
			cframes(c, 4)
			local card = c.h.localPlayer.PlayerGui.Panels.Safe.CrewInvite
			local accept, decline = card.Accept, card.Decline
			local pad = accept.PadGlyph
			-- en jeu, rien n'est sélectionné : ✕ ferait sauter le personnage, la carte montre △
			expect(Gamepad.selected(c.h)).toBeNil()
			expect(pad:GetAttribute("GlyphKey")).toBe("ButtonY")
			expect(table.concat(Gamepad.audit(c.h, { root = card }), "\n")).toBe("")
			-- △ sélectionne Accepter : le repère devient ✕
			Gamepad.tap(c.h, K.ButtonY)
			expect(Gamepad.selected(c.h)).toBe(accept)
			expect(pad:GetAttribute("GlyphKey")).toBe("ButtonA")
			expect(table.concat(Gamepad.audit(c.h, { root = card }), "\n")).toBe("")
			-- → Refuser : ✕ refuserait et △ effacerait la sélection ; le repère d'Accepter montre ←
			Gamepad.tap(c.h, K.DPadRight)
			expect(Gamepad.selected(c.h)).toBe(decline)
			expect(pad:GetAttribute("GlyphKey")).toBe("DPadLeft")
			expect(table.concat(Gamepad.audit(c.h, { root = card }), "\n")).toBe("")
			Gamepad.tap(c.h, K.DPadLeft)
			expect(pad:GetAttribute("GlyphKey")).toBe("ButtonA")
			-- ✕ rejoint ; carte retirée, sélection effacée, repère revenu à △ pour la suivante
			Gamepad.tap(c.h, K.ButtonA)
			cframes(c, 2)
			local respond = sentCount(c, "CrewRespond")
			expect(#respond).toBe(1)
			expect(respond[1][1]).toBe(2)
			expect(respond[1][2]).toBe(true)
			expect(card.Visible).toBe(false)
			expect(pad:GetAttribute("GlyphKey")).toBe("ButtonY")
			expect(table.concat(c.h.errors, "\n")).toBe("")
		end)
	end)
	-- =============================================================================================
	-- ScreenFX : l'onde de choc et le Nebby fantôme d'un achat attendent la fermeture du panneau
	-- =============================================================================================
	local function fxSetup(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", touch = opts.touch })
		h.localPlayer.LocaleId = "en-us"
		h:createRemotes()
		if opts.viewport then
			h.workspace.CurrentCamera.ViewportSize = opts.viewport
		end
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = {
			h = h,
			Clock = Clock,
			Root = h:require(CLIENT .. "UI.Root"),
			State = h:require(CLIENT .. "Controllers.StateController"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			WSC = h:require(CLIENT .. "Controllers.WorldStateController"),
			VFX = h:require(CLIENT .. "Controllers.VFXController"),
			FX = h:require(CLIENT .. "UI.ScreenFX"),
			vfx = {},
			open = nil,
		}
		c.VFX.playUpgrade = function(track, level)
			table.insert(c.vfx, { track = track, level = level })
		end
		c.WSC.localSlot = function()
			return 1
		end
		c.WSC.lineLength = function()
			return 0
		end
		c.Root.Init()
		c.State.Init()
		c.Prefs.Init()
		c.Prefs.Start()
		c.FX.Init()
		c.FX.Start()
		c.FX.setPanelResolver(function()
			return c.open
		end)
		return c
	end

	local function upgrade(c, track, level)
		c.h:fireClient(REMOTES .. "Celebrate", { kind = "upgrade", data = { track = track, level = level } })
	end

	describe("Fix r3 ui-1 › ScreenFX : juice du premier achat visible", function()
		it("achat panneau Améliorer ouvert : effet joué après la fermeture, une seule fois", function()
			local c = fxSetup()
			c.open = "Upgrades"
			upgrade(c, "conga", 1)
			-- le « +1 » flottant reste immédiat (couche au-dessus des panneaux)
			local floating = 0
			for _, f in c.FX._state().floaters do
				if f.busy then
					floating += 1
				end
			end
			expect(floating).toBe(1)
			-- sous le voile et le flou : rien n'est joué dans le monde
			expect(#c.vfx).toBe(0)
			c.h:step(1 / 30, 18) -- 0,6 s : fermeture automatique de l'accueil
			expect(#c.vfx).toBe(0)
			c.open = nil
			c.h:step(1 / 30, 1)
			expect(#c.vfx).toBe(0) -- le fondu de fermeture (0,12 s) se termine d'abord
			c.h:step(1 / 30, 9)
			expect(#c.vfx).toBe(1)
			expect(c.vfx[1].track).toBe("conga")
			expect(c.vfx[1].level).toBe(1)
			c.h:step(1 / 30, 30)
			expect(#c.vfx).toBe(1)
		end)

		it("plusieurs achats panneau ouvert : seul le dernier est rejoué ; oublié après 10 s", function()
			local c = fxSetup()
			c.open = "Upgrades"
			upgrade(c, "conga", 2)
			upgrade(c, "stride", 1)
			c.h:step(1 / 30, 3)
			c.open = nil
			c.h:step(1 / 30, 12)
			expect(#c.vfx).toBe(1)
			expect(c.vfx[1].track).toBe("stride")
			-- panneau resté ouvert longtemps : l'effet n'a plus de sens, il n'est pas joué
			c.open = "Upgrades"
			upgrade(c, "lure", 1)
			c.h:step(0.25, 44) -- 11 s
			c.open = nil
			c.h:step(1 / 30, 30)
			expect(#c.vfx).toBe(1)
			-- aucun panneau : joué tout de suite, comme avant
			upgrade(c, "perches", 3)
			expect(#c.vfx).toBe(2)
			expect(c.vfx[2].track).toBe("perches")
		end)
	end)
	-- =============================================================================================
	-- ScreenFX : cartes « NOUVEAU ! » jamais sur le Dash, le Ping ni le bouton de saut ; zone sûre
	-- =============================================================================================
	local Nebbies = Harness.new():require("ReplicatedStorage.Shared.Config.Nebbies")

	-- bouton de saut tactile de Roblox : 70 px à (1, −95, 1, −90) sur petit écran, 120 px à
	-- (1, −170, 1, −210) sinon (écran sous la barre Roblox)
	local function addJump(c, viewport)
		local Instance = c.h.globals.Instance
		local touchGui = Instance.new("ScreenGui")
		touchGui.Name = "TouchGui"
		local frame = Instance.new("Frame")
		frame.Name = "TouchControlFrame"
		frame.Size = roblox.UDim2.fromScale(1, 1)
		frame.BackgroundTransparency = 1
		frame.Parent = touchGui
		local jump = Instance.new("ImageButton")
		jump.Name = "JumpButton"
		local small = math.min(viewport.X, viewport.Y) < 500
		jump.Size = if small then roblox.UDim2.fromOffset(70, 70) else roblox.UDim2.fromOffset(120, 120)
		jump.Position = if small then roblox.UDim2.new(1, -95, 1, -90) else roblox.UDim2.new(1, -170, 1, -210)
		jump.Parent = frame
		touchGui.Parent = c.h.localPlayer.PlayerGui
		return jump
	end

	-- HUD complet mesuré sur l'écran donné (Dash placé contre le bouton de saut, colonne de droite
	-- rangée), état et suivi de quête affichés
	local function measuredHud(viewport, touch)
		local c = hudSetup({ touch = touch, viewport = viewport })
		snapshot(c, { onboarding = { step = 3, p = 0 } })
		c.HUD.revealAll()
		local jump = if touch then addJump(c, viewport) else nil
		for _ = 1, 3 do
			Layout.apply(c.h)
			c.HUD._layoutActions()
			frames(c, 12)
		end
		Layout.apply(c.h)
		return c, jump
	end

	local function atlasNew(c, n)
		local entries = {}
		for s = 1, n do
			table.insert(entries, { s = s, f = 0 })
		end
		c.FX._onCelebrate({ kind = "atlasNew", data = { entries = entries } })
		frames(c, 15) -- 0,5 s : les cartes ont fini de glisser
		Layout.apply(c.h)
	end

	local function shownCards(c)
		local out = {}
		for _, card in c.FX._state().cardList do
			table.insert(out, card.frame)
		end
		return out
	end

	local function expectClear(label, cards, rects)
		for i, card in cards do
			local r = Layout.rect(card)
			for name, other in rects do
				expect({ screen = label, card = i, other = name, overlap = intersects(r, other) }).toEqual({
					screen = label,
					card = i,
					other = name,
					overlap = false,
				})
			end
		end
	end

	describe("Fix r3 ui-1 › cartes « NOUVEAU ! » de l'Atlas", function()
		for _, size in
			{ Vector2.new(844, 390), Vector2.new(800, 360), Vector2.new(667, 375), Vector2.new(568, 320) }
		do
			it(
				`téléphone {size.X} × {size.Y} : ni Dash, ni Ping, ni saut ; les autres attendent`,
				function()
					local c, jump = measuredHud(size, true)
					local hud = hud(c)
					atlasNew(c, 3)
					local cards = shownCards(c)
					expect(#cards >= 1).toBe(true)
					expect(#cards + c.FX._state().queuedCards).toBe(3)
					expectClear(`{size.X}x{size.Y}`, cards, {
						dash = Layout.rect(hud.Dash),
						ping = Layout.rect(hud.Ping),
						jump = Layout.rect(jump),
					})
					for _, card in cards do
						local r = Layout.rect(card)
						expect(r.x >= 0 and r.y >= 0 and r.x + r.w <= size.X and r.y + r.h <= size.Y).toBe(
							true
						)
					end
					-- la file passe ensuite, toujours au même endroit sûr
					for _ = 1, 4 do
						frames(c, 45)
						Layout.apply(c.h)
						expectClear(`{size.X}x{size.Y} (suite)`, shownCards(c), {
							dash = Layout.rect(hud.Dash),
							ping = Layout.rect(hud.Ping),
							jump = Layout.rect(jump),
						})
					end
					expect(c.FX._state().queuedCards).toBe(0)
				end
			)
		end

		it("PC 1280 × 720 : pile sous la colonne de droite, sans la toucher, au-dessus du Dash", function()
			local c = measuredHud(Vector2.new(1280, 720), false)
			local hud = hud(c)
			atlasNew(c, 3)
			local cards = shownCards(c)
			expect(#cards >= 2).toBe(true)
			expectClear("1280x720", cards, {
				dash = Layout.rect(hud.Dash),
				ping = Layout.rect(hud.Ping),
				status = Layout.rect(hud.Status),
				tracker = Layout.rect(hud.QuestTracker),
				-- minicarte (écran Minimap) : 150 × 150 à (−16, 16) de la zone intérieure (marges 12 × 8)
				minimap = { x = 1280 - 12 - 16 - 150, y = 58 + 8 + 16, w = 150, h = 150 },
			})
			-- bord droit de la pile = bord droit de la colonne du HUD (zone sûre + marge de 16 px)
			local r = Layout.rect(cards[1])
			local status = Layout.rect(hud.Status)
			expect(r.x + r.w).toBeNear(status.x + status.w, 0.5)
			-- sous la colonne : plus haut que l'ancienne place à 42 % de l'écran n'est pas exigé, mais la
			-- pile commence sous le suivi de quête
			local tracker = Layout.rect(hud.QuestTracker)
			expect(r.y >= tracker.y + tracker.h).toBe(true)
		end)

		it("encoche à droite (zone sûre plus étroite) : la carte reste dans la zone sûre", function()
			local size = Vector2.new(844, 390)
			local c = measuredHud(size, true)
			-- ScreenInsets = CoreUISafeInsets : l'écran du HUD perd 44 px à droite (encoche)
			local gui = c.h.localPlayer.PlayerGui.HUD
			gui.AbsoluteSize = Vector2.new(size.X - 44, gui.AbsoluteSize.Y)
			atlasNew(c, 1)
			local cards = shownCards(c)
			expect(#cards).toBe(1)
			local r = Layout.rect(cards[1])
			expect(r.x + r.w <= size.X - 44 + 1e-6).toBe(true)
		end)
	end)
end
