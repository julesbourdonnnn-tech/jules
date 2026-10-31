--!nocheck
-- QA round 4 — fixer r4-ui-1, HUD (src/client/UI/HUD.luau) :
--   * téléphones 16:9 étroits (640 × 360, 667 × 375) : la pastille d'événement (et la barre de la
--     Balise) ne recouvre plus Équipage / Réglages ni la minicarte ; centrée dès qu'il y a la place ;
--     la place des cartes « NOUVEAU ! » évite la pastille décalée ;
--   * manette pendant l'accueil : △ va d'abord à la carte d'invitation d'équipage (passagère, 20 s,
--     sur un autre ScreenGui) avant la cible de l'accueil ; l'icône △ du rail s'efface tant que la
--     carte l'annonce (docs/07 §6.7).
local roblox = require("@lune/roblox")
local Gamepad = require("../harness/Gamepad")

local Vector2 = roblox.Vector2
local UDim2 = roblox.UDim2
local K = roblox.Enum.KeyCode

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000

	-- =========================================================================================
	-- Pastille d'événement sur téléphone (même montage que Fix_client-hud_r2)
	-- =========================================================================================

	local function hudSetup()
		local h = Harness.new({ mode = "client", touch = true })
		h.localPlayer.LocaleId = "en-us"
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = {
			h = h,
			g = h.globals,
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
		}
		c.VFX.playDash = function() end
		c.WSC.localSlot = function()
			return 1
		end
		c.Root.Init()
		c.State.Init()
		c.Prefs.Init()
		c.Prefs.Start()
		c.FX.Init()
		c.Input.Init()
		-- la place des cartes « NOUVEAU ! » que le HUD confie à ScreenFX (HUD.Init)
		local setCardPlacer = c.FX.setCardPlacer
		c.FX.setCardPlacer = function(fn)
			c.cardPlacement = fn
			setCardPlacer(fn)
		end
		c.HUD.Init()
		c.FX.Start()
		c.Input.Start()
		c.HUD.Start()
		c.HUD.revealAll()
		return c
	end

	local function hud(c)
		return c.h.localPlayer.PlayerGui.HUD.Safe
	end

	local function screen(c, width, height, topbar)
		c.h.workspace.CurrentCamera.ViewportSize = Vector2.new(width, height)
		local gui = c.h.localPlayer.PlayerGui.HUD
		gui.AbsoluteSize = Vector2.new(width, height - topbar)
		hud(c).AbsoluteSize = gui.AbsoluteSize
		local playerGui = c.h.localPlayer.PlayerGui
		local touchGui = playerGui:FindFirstChild("TouchGui")
		if touchGui == nil then
			touchGui = c.g.Instance.new("ScreenGui")
			touchGui.Name = "TouchGui"
			local frame = c.g.Instance.new("Frame")
			frame.Name = "TouchControlFrame"
			frame.Parent = touchGui
			local jump = c.g.Instance.new("ImageButton")
			jump.Name = "JumpButton"
			jump.Parent = frame
			touchGui.Parent = playerGui
		end
		local jump = touchGui.TouchControlFrame.JumpButton
		local small = math.min(width, height) < 500
		local size = if small then 70 else 120
		local offset = if small then Vector2.new(-95, -90) else Vector2.new(-170, -210)
		jump.AbsoluteSize = Vector2.new(size, size)
		jump.AbsolutePosition = Vector2.new(width, height - topbar) + offset
		c.HUD._layoutActions()
		c.h:settle(1)
	end

	-- rectangle d'un élément en px de référence du HUD (zone intérieure W × H)
	local function rect(c, holder)
		local gui = c.h.localPlayer.PlayerGui.HUD
		local k = c.Root.scale()
		local W = gui.AbsoluteSize.X / k - 24
		local H = gui.AbsoluteSize.Y / k - 16
		local p, s, a = holder.Position, holder.Size, holder.AnchorPoint
		local x = p.X.Scale * W + p.X.Offset - a.X * s.X.Offset
		local y = p.Y.Scale * H + p.Y.Offset - a.Y * s.Y.Offset
		return { x0 = x, y0 = y, x1 = x + s.X.Offset, y1 = y + s.Y.Offset, W = W, H = H }
	end

	-- barre de la Balise : ancrée (0,5 ; 0) en (0,5 ; 1 + 6) dans la pastille
	local function barRect(pill, bar)
		local cx = (pill.x0 + pill.x1) / 2
		local w = bar.Size.X.Offset
		local y = pill.y1 + bar.Position.Y.Offset
		return { x0 = cx - w / 2, y0 = y, x1 = cx + w / 2, y1 = y + bar.Size.Y.Offset, W = pill.W, H = pill.H }
	end

	local function overlap(a, b)
		return a.x0 < b.x1 and b.x0 < a.x1 and a.y0 < b.y1 and b.y0 < a.y1
	end

	local function inside(r)
		return r.x0 >= 0 and r.y0 >= 0 and r.x1 <= r.W + 1e-6 and r.y1 <= r.H + 1e-6
	end

	local function expectApart(label, named, a, b)
		expect({ screen = label, a = a, b = b, overlap = overlap(named[a], named[b]) }).toEqual({
			screen = label,
			a = a,
			b = b,
			overlap = false,
		})
	end

	-- Blocs du haut et de la colonne de droite. Toutes les paires (Équipage et Réglages compris, ce
	-- que Fix_client-hud_r2 ne vérifiait pas) ; `topOnly` : seulement la pastille et la barre de la
	-- Balise face au reste (écrans trop bas pour la colonne de droite, hors sujet ici). La barre de
	-- la Balise n'est comparée qu'à la rangée du haut et à la minicarte : quand elle n'a pas la place,
	-- layoutColumn range volontairement le suivi de quête sous la pastille seule (repli existant).
	local function checkLayout(c, label, topOnly)
		local safe = hud(c)
		local dash = rect(c, safe.Dash)
		local W = dash.W
		local pill = rect(c, safe.EventPill)
		local named = {
			dash = dash,
			ping = rect(c, safe.Ping),
			tracker = rect(c, safe.QuestTracker),
			status = rect(c, safe.Status),
			pill = pill,
			bar = barRect(pill, safe.EventPill.BeaconBar),
			crew = rect(c, safe.crew),
			settings = rect(c, safe.settings),
			minimap = { x0 = W - 166, y0 = 16, x1 = W - 16, y1 = 166, W = W, H = dash.H },
		}
		local order = { "dash", "ping", "tracker", "status", "pill", "crew", "settings", "minimap" }
		for i, a in order do
			for j = i + 1, #order do
				local b = order[j]
				local concerned = not topOnly or a == "pill" or b == "pill"
				if concerned and not (a == "dash" and b == "ping") then
					expectApart(label, named, a, b)
				end
			end
		end
		for _, b in { "crew", "settings", "minimap" } do
			expectApart(label, named, "bar", b)
		end
		for name, r in named do
			expect({ screen = label, name = name, inside = inside(r) }).toEqual({
				screen = label,
				name = name,
				inside = true,
			})
		end
		return named
	end

	describe("Fix r4-ui-1 › pastille d'événement et Réglages sur téléphone", function()
		it("640 × 360 et 667 × 375 : la pastille laisse Réglages libre (repro du rapport)", function()
			local c = hudSetup()
			for _, size in { { 640, 360, 36 }, { 667, 375, 36 } } do
				screen(c, size[1], size[2], size[3])
				local label = size[1] .. "x" .. size[2]
				local r = checkLayout(c, label)
				-- au moins 8 px d'écart avec Réglages, entièrement à gauche de la minicarte
				expect({ label = label, gap = r.pill.x0 - r.settings.x1 >= 8 }).toEqual({
					label = label,
					gap = true,
				})
				expect({ label = label, gap = r.minimap.x0 - r.pill.x1 >= 8 }).toEqual({
					label = label,
					gap = true,
				})
				-- pleine largeur (320) : il y a la place une fois décalée
				expect(r.pill.x1 - r.pill.x0).toBe(320)
				-- décalages UDim entiers
				local pos = hud(c).EventPill.Position
				expect(pos.X.Offset % 1).toBe(0)
			end
		end)

		it("barre de la Balise affichée : ni sur Réglages ni sur la minicarte", function()
			local c = hudSetup()
			hud(c).EventPill.BeaconBar.Visible = true
			for _, size in
				{ { 640, 360, 36 }, { 667, 375, 36 }, { 568, 320, 36 }, { 800, 360, 58 }, { 844, 390, 36 } }
			do
				screen(c, size[1], size[2], size[3])
				checkLayout(c, size[1] .. "x" .. size[2] .. "/" .. size[3] .. " + Balise", size[1] == 568)
			end
		end)

		it("autres écrans : aucun chevauchement, Équipage et Réglages compris", function()
			local c = hudSetup()
			-- iPhone SE (1re génération) : la colonne de droite n'y tient pas (déjà le cas avant),
			-- seule la rangée du haut est vérifiée
			screen(c, 568, 320, 36)
			checkLayout(c, "568x320/36", true)
			for _, size in
				{
					{ 780, 360, 36 },
					{ 800, 360, 36 },
					{ 800, 360, 58 },
					{ 844, 390, 36 },
					{ 1024, 768, 36 },
				}
			do
				screen(c, size[1], size[2], size[3])
				checkLayout(c, size[1] .. "x" .. size[2] .. "/" .. size[3])
			end
		end)

		it("écran large : pastille centrée comme au GDD, barre de la Balise à 420", function()
			local c = hudSetup()
			screen(c, 1024, 768, 36)
			screen(c, 640, 360, 36)
			expect(hud(c).EventPill.Position ~= UDim2.new(0.5, 0, 0, 16)).toBe(true)
			-- PC 1920 × 1080 (clavier)
			c.h.game.UserInputService.LastInputTypeChanged:Fire(roblox.Enum.UserInputType.Keyboard)
			c.h:settle(1)
			c.h.workspace.CurrentCamera.ViewportSize = Vector2.new(1920, 1080)
			c.h.localPlayer.PlayerGui.HUD.AbsoluteSize = Vector2.new(1920, 1044)
			c.HUD._layoutActions()
			expect(hud(c).EventPill.Position).toEqual(UDim2.new(0.5, 0, 0, 16))
			expect(hud(c).EventPill.Size).toEqual(UDim2.fromOffset(320, 48))
			expect(hud(c).EventPill.BeaconBar.Size.X.Offset).toBe(420)
		end)

		it(
			"cartes « NOUVEAU ! » : jamais sur la pastille décalée (barre de la Balise comprise)",
			function()
				local c = hudSetup()
				expect(c.cardPlacement ~= nil).toBe(true)
				local safe = hud(c)
				for _, withBar in { false, true } do
					safe.EventPill.BeaconBar.Visible = withBar
					for _, size in { { 640, 360, 36 }, { 667, 375, 36 } } do
						screen(c, size[1], size[2], size[3])
						for _, width in { 160, 220 } do
							local place = c.cardPlacement(Vector2.new(width, 64), 8, 3)
							expect(place ~= nil).toBe(true)
							-- px de fenêtre → px de référence de la zone intérieure (inverse de toViewport)
							local k = c.Root.scale()
							local pad = safe:FindFirstChildOfClass("UIPadding")
							local inset = c.h.game.GuiService:GetGuiInset()
							local origin = safe.AbsolutePosition
							local right = (place.right - origin.X - inset.X) / k - pad.PaddingLeft.Offset
							local top = (place.top - origin.Y - inset.Y) / k - pad.PaddingTop.Offset
							local stack = {
								x0 = right - width,
								y0 = top,
								x1 = right,
								y1 = top + place.count * 64 + (place.count - 1) * 8,
							}
							local pill = rect(c, safe.EventPill)
							local label = size[1]
								.. "x"
								.. size[2]
								.. "/"
								.. width
								.. (if withBar then "+Balise" else "")
							expect({ label = label, pill = overlap(stack, pill) }).toEqual({
								label = label,
								pill = false,
							})
							if withBar then
								local bar = barRect(pill, safe.EventPill.BeaconBar)
								expect({ label = label, bar = overlap(stack, bar) }).toEqual({
									label = label,
									bar = false,
								})
							end
						end
					end
				end
			end
		)
	end)

	-- =========================================================================================
	-- Manette : △ pendant l'accueil avec une carte d'invitation d'équipage
	-- =========================================================================================

	local Schema = Harness.new():require("ServerScriptService.Server.Data.Schema")

	local function consoleBoot(over)
		local h = Harness.new({ mode = "client", console = true })
		h.localPlayer.LocaleId = "en-us"
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		h:boot()
		local p = Schema.defaults()
		p.lastSettle = T0
		p.lastOnline = T0
		p.settings.lang = "en"
		p.settings.refuseInvites = false
		for k, v in over or {} do
			p[k] = v
		end
		h:fireClient(REMOTES .. "DataSnapshot", p)
		h:step(1 / 60, 30)
		h:settle(3)
		return {
			h = h,
			Clock = Clock,
			HUD = h:require(CLIENT .. "UI.HUD"),
			PC = h:require(CLIENT .. "Controllers.PanelController"),
			Onboarding = h:require(CLIENT .. "Controllers.OnboardingController"),
		}
	end

	local function cframes(c, n)
		for _ = 1, n or 3 do
			c.Clock.advance(1 / 30)
			c.h:step(1 / 30, 1)
		end
		c.h:settle(1)
	end

	local function triangle(c)
		c.h.game.GuiService.SelectedObject = nil
		c.h:settle(1)
		Gamepad.tap(c.h, K.ButtonY)
		return Gamepad.selected(c.h)
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

	describe("Fix r4-ui-1 › △ : carte d'invitation avant la cible de l'accueil", function()
		it(
			"Q2, Améliorer pulse : △ sélectionne Accepter, ✕ rejoint ; ensuite △ revient au rail",
			function()
				-- Q2 « Conga ×2 », Conga 2 payable : le rail Améliorer pulse (cible de l'accueil)
				local c = consoleBoot({
					glow = 500,
					upgrades = { conga = 1, stride = 0, lure = 0, perches = 0, guard = 0 },
					onboarding = { step = 2, p = 0 },
				})
				cframes(c, 20)
				local railUpgrades = c.h.localPlayer.PlayerGui.HUD.Safe.Rail.Upgrades.Button
				local state = c.HUD._state()
				expect(state.elements["rail.Upgrades"].attention).toBe(true)
				-- sans carte : △ va à la cible de l'accueil, l'icône du rail annonce △
				expect(triangle(c)).toBe(railUpgrades)
				c.h.game.GuiService.SelectedObject = nil
				cframes(c, 3)
				local hand = state.handGlyph.frame
				expect(hand:GetAttribute("GlyphKey")).toBe("ButtonY")
				-- invitation (20 s) : la carte montre △ sur Accepter, △ la sélectionne
				c.h:addPlayer({ userId = 2, name = "Mira" })
				c.h:settle(2)
				c.h:fireClient(REMOTES .. "CrewInvitePrompt", { inviterId = 2, expiresAt = T0 + 20 })
				cframes(c, 4)
				local card = c.h.localPlayer.PlayerGui.Panels.Safe.CrewInvite
				expect(card.Visible).toBe(true)
				expect(card.Accept.PadGlyph:GetAttribute("GlyphKey")).toBe("ButtonY")
				-- un seul △ à l'écran : celui de la carte (plus celui du rail)
				expect(hand:GetAttribute("GlyphKey") or "").toBe("")
				expect(triangle(c)).toBe(card.Accept)
				-- ✕ rejoint l'équipage
				Gamepad.tap(c.h, K.ButtonA)
				cframes(c, 3)
				local respond = sentCount(c, "CrewRespond")
				expect(#respond).toBe(1)
				expect(respond[1][2]).toBe(true)
				expect(card.Visible).toBe(false)
				-- carte partie : l'accueil reprend la main
				expect(triangle(c)).toBe(railUpgrades)
				c.h.game.GuiService.SelectedObject = nil
				cframes(c, 3)
				expect(hand:GetAttribute("GlyphKey")).toBe("ButtonY")
				expect(table.concat(c.h.errors, "\n")).toBe("")
			end
		)
	end)
end
