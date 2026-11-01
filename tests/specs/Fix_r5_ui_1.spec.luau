--!nocheck
-- Finition r5 (fixer r5-ui-1) : carte d'invitation d'équipage (src/client/UI/Panels/Crew.luau) placée
-- dans la place libre du HUD (ScreenFX.cardPlacement / ScreenFX.hudObstacles).
--   Avant : carte fixe de 360 × 156 px de référence en (1, −16, 0,42) dans Root.safe("Panels")
--   (DisplayOrder 30, au-dessus du HUD) : sur un téléphone 640 × 360 sous la barre de 58 px, Accepter /
--   Refuser couvraient la moitié haute du Dash, le Ping, le suivi de quête et le bas de la minicarte ;
--   même chose en 667 × 375 ; sur PS5 en 1080p, la carte couvrait le suivi de quête et l'état
--   pendant 20 s.
--   Maintenant : la place libre que le HUD donne dans sa colonne de droite si elle ne recouvre aucun
--   élément affiché ; sinon en haut au centre sous la rangée des bannières, plus bas ou décalée si
--   un bloc y est ; jamais dans le coin des actions (Dash, Ping, bouton de saut) ni sur la pastille
--   d'événement, la minicarte, l'état ou le suivi ; la carte suit les changements de mise en page.
local roblox = require("@lune/roblox")
local Layout = require("../harness/Layout")
local MockInstance = require("../harness/MockInstance")

local Vector2 = roblox.Vector2
local UDim2 = roblox.UDim2

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000
	local DEFAULT_INSET = Layout.GUI_INSET

	local Schema = Harness.new():require("ServerScriptService.Server.Data.Schema")

	-- barre Roblox de `topbar` px (Layout et GuiService:GetGuiInset) ; rétablie par `finish`
	local function setInset(topbar)
		Layout.GUI_INSET = topbar
		MockInstance.classMethods.GuiService.GetGuiInset = function()
			return Vector2.new(0, topbar), Vector2.zero
		end
	end

	-- bouton de saut tactile de Roblox : (1, −95, 1, −90) 70 px sur un petit écran (GDD §10.1)
	local function touchGui(h, size)
		local playerGui = h.localPlayer.PlayerGui
		local gui = h.globals.Instance.new("ScreenGui")
		gui.Name = "TouchGui"
		local frame = h.globals.Instance.new("Frame")
		frame.Name = "TouchControlFrame"
		frame.Size = UDim2.fromScale(1, 1)
		frame.Parent = gui
		local jump = h.globals.Instance.new("ImageButton")
		jump.Name = "JumpButton"
		local small = math.min(size.X, size.Y) < 500
		jump.Size = if small then UDim2.fromOffset(70, 70) else UDim2.fromOffset(120, 120)
		jump.Position = if small then UDim2.new(1, -95, 1, -90) else UDim2.new(1, -170, 1, -210)
		jump.Parent = frame
		gui.Parent = playerGui
		return jump
	end

	local function settleLayout(c, rounds)
		for _ = 1, rounds or 4 do
			Layout.apply(c.h)
			c.Clock.advance(1.2)
			c.h:step(0.1, 12)
			c.h:settle(1)
		end
		Layout.apply(c.h)
	end

	-- Client complet (Main.client), HUD entièrement révélé, écran mesuré (Layout)
	local function boot(size, topbar, opts)
		opts = opts or {}
		setInset(topbar)
		local h = Harness.new({ mode = "client", touch = opts.touch, console = opts.console })
		setInset(topbar)
		h.localPlayer.LocaleId = "en-us"
		h:createRemotes()
		h.workspace.CurrentCamera.ViewportSize = size
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local jump = if opts.touch then touchGui(h, size) else nil
		h:boot()
		local p = Schema.defaults()
		p.lastSettle = T0
		p.lastOnline = T0
		p.settings.lang = "en"
		p.settings.refuseInvites = false
		p.onboarding = { step = opts.step or 8, p = 0 }
		h:fireClient(REMOTES .. "DataSnapshot", p)
		h:step(1 / 60, 30)
		h:settle(3)
		local c = {
			h = h,
			Clock = Clock,
			jump = jump,
			HUD = h:require(CLIENT .. "UI.HUD"),
			FX = h:require(CLIENT .. "UI.ScreenFX"),
			Crew = h:require(CLIENT .. "UI.Panels.Crew"),
		}
		if opts.reveal ~= false then
			c.HUD.revealAll()
		end
		settleLayout(c)
		return c
	end

	local function finish(c)
		expect(table.concat(c.h.errors, "\n")).toBe("")
		setInset(DEFAULT_INSET)
	end

	local function invite(c, ttl)
		c.h:addPlayer({ userId = 2, name = "Mira" })
		c.h:settle(2)
		c.h:fireClient(
			REMOTES .. "CrewInvitePrompt",
			{ inviterId = 2, expiresAt = c.Clock.now() + (ttl or 20) }
		)
		c.h:step(0.1, 10)
		c.h:settle(1)
		Layout.apply(c.h)
		return c.h.localPlayer.PlayerGui.Panels.Safe.CrewInvite
	end

	local function rect(obj)
		local r = Layout.rect(obj)
		return { x0 = r.x, y0 = r.y, x1 = r.x + r.w, y1 = r.y + r.h }
	end

	local function overlap(a, b)
		return a.x0 < b.x1 and b.x0 < a.x1 and a.y0 < b.y1 and b.y0 < a.y1
	end

	local function fmt(r)
		return string.format("x %d-%d y %d-%d", r.x0, r.x1, r.y0, r.y1)
	end

	-- La carte, Accepter et Refuser ne touchent ni le Dash, ni le Ping, ni le suivi de quête, ni
	-- l'état, ni la minicarte, ni la pastille d'événement (ni le bouton de saut tactile) ; tout
	-- reste dans l'écran sous la barre Roblox
	-- `allow` : blocs que la carte peut recouvrir dans ce cas (aucune autre place)
	local function expectClear(c, card, label, allow)
		local playerGui = c.h.localPlayer.PlayerGui
		local hud = playerGui.HUD.Safe
		expect({ screen = label, visible = Layout.visible(card) }).toEqual({ screen = label, visible = true })
		local blocks = {
			Dash = hud.Dash,
			Ping = hud.Ping,
			QuestTracker = hud.QuestTracker,
			Status = hud.Status,
			EventPill = hud.EventPill,
			Cheer = hud.Cheer,
			LineCounter = hud.LineCounter,
			Minimap = playerGui.Minimap.Safe.Minimap,
			JumpButton = c.jump,
		}
		for _, name in allow or {} do
			blocks[name] = nil
		end
		local bad = {}
		for _, part in { card, card.Accept, card.Decline } do
			local r = rect(part)
			for name, block in blocks do
				if block ~= nil and Layout.visible(block) and overlap(r, rect(block)) then
					table.insert(bad, `{part.Name} ({fmt(r)}) sur {name} ({fmt(rect(block))})`)
				end
			end
		end
		table.sort(bad)
		expect({ screen = label, overlaps = table.concat(bad, "\n") }).toEqual({
			screen = label,
			overlaps = "",
		})
		local r = rect(card)
		local size = c.h.workspace.CurrentCamera.ViewportSize
		local inside = r.x0 >= 0 and r.x1 <= size.X and r.y0 >= Layout.GUI_INSET and r.y1 <= size.Y
		expect({ screen = label, card = fmt(r), inside = inside }).toEqual({
			screen = label,
			card = fmt(r),
			inside = true,
		})
		return r
	end

	describe("Fix r5 ui-1 › carte d'invitation d'équipage : jamais sur le HUD", function()
		local CASES = {
			{ label = "640 × 360 / 58 (toucher)", size = Vector2.new(640, 360), topbar = 58, touch = true },
			{ label = "667 × 375 / 36 (toucher)", size = Vector2.new(667, 375), topbar = 36, touch = true },
			{ label = "844 × 390 / 36 (toucher)", size = Vector2.new(844, 390), topbar = 36, touch = true },
			{ label = "PS5 1920 × 1080", size = Vector2.new(1920, 1080), topbar = 58, console = true },
			{ label = "PC 1280 × 720", size = Vector2.new(1280, 720), topbar = 58 },
			{ label = "tablette 1024 × 768 / 36", size = Vector2.new(1024, 768), topbar = 36, touch = true },
		}
		for _, case in CASES do
			it(`{case.label} : la carte (Accepter, Refuser) laisse le HUD libre`, function()
				local c = boot(case.size, case.topbar, { touch = case.touch, console = case.console })
				local card = invite(c)
				expectClear(c, card, case.label)
				-- la carte reste répondable : Accepter envoie la réponse, la carte part
				expect(c.Crew.inviteTarget()).toBe(card.Accept)
				finish(c)
			end)
		end

		it("PC 1280 × 720 : la carte va dans la colonne de droite (place du HUD, sous le suivi)", function()
			local c = boot(Vector2.new(1280, 720), 58)
			local card = invite(c)
			local r = expectClear(c, card, "PC 1280 × 720")
			local hud = c.h.localPlayer.PlayerGui.HUD.Safe
			local minimap = rect(c.h.localPlayer.PlayerGui.Minimap.Safe.Minimap)
			local tracker = rect(hud.QuestTracker)
			-- bord droit aligné sur la minicarte, sous le suivi de quête et au-dessus du Dash
			expect(math.abs(r.x1 - minimap.x1) < 1.5).toBe(true)
			expect(r.y0 >= tracker.y1).toBe(true)
			expect(r.y1 <= rect(hud.Dash).y0).toBe(true)
			finish(c)
		end)

		it("téléphone 640 × 360 : sous la rangée des bannières et hors du quart du joystick", function()
			local c = boot(Vector2.new(640, 360), 58, { touch = true })
			local card = invite(c)
			local r = expectClear(c, card, "640 × 360")
			local k = c.h:require(CLIENT .. "UI.Root").scale()
			-- rangée des bannières (UI/Banners : y 72, 72 px de haut) dans la zone intérieure
			local padding = c.h.localPlayer.PlayerGui.Panels.Safe:FindFirstChildOfClass("UIPadding")
			local bannersBottom = Layout.GUI_INSET + (padding.PaddingTop.Offset + 72 + 72) * k
			expect(r.y0 >= bannersBottom - 0.5).toBe(true)
			-- le quart inférieur gauche reste au joystick dynamique (GDD §10.1)
			local size = c.h.workspace.CurrentCamera.ViewportSize
			local joystick = {
				x0 = 0,
				y0 = Layout.GUI_INSET + 0.75 * (size.Y - Layout.GUI_INSET),
				x1 = size.X / 2,
				y1 = size.Y,
			}
			expect(overlap(r, joystick)).toBe(false)
			finish(c)
		end)

		it("la carte suit la mise en page : fenêtre PC réduite pendant l'invitation", function()
			local c = boot(Vector2.new(1280, 720), 58)
			local card = invite(c)
			local before = expectClear(c, card, "PC 1280 × 720")
			-- la fenêtre devient basse et étroite : le HUD se range, la carte aussi
			c.h.workspace.CurrentCamera.ViewportSize = Vector2.new(800, 400)
			settleLayout(c)
			expect(card.Visible).toBe(true)
			local after = expectClear(c, card, "PC 800 × 400")
			expect(after.x0 ~= before.x0 or after.y0 ~= before.y0).toBe(true)
			finish(c)
		end)

		it("ACCLAMER affiché (844 × 390) : la carte ne couvre pas le bouton", function()
			local c = boot(Vector2.new(844, 390), 36, { touch = true })
			local card = invite(c)
			expectClear(c, card, "844 × 390")
			c.HUD._onCheerPrompt({ heroId = 42, level = 3, expiresAt = c.Clock.now() + 10 })
			settleLayout(c, 1)
			local hud = c.h.localPlayer.PlayerGui.HUD.Safe
			expect(Layout.visible(hud.Cheer)).toBe(true)
			expectClear(c, card, "844 × 390, ACCLAMER")
			finish(c)
		end)

		it("ACCLAMER affiché (640 × 360) : jamais sur ACCLAMER, le Dash ni le Ping", function()
			local c = boot(Vector2.new(640, 360), 58, { touch = true })
			-- invitation longue (le serveur prolonge la carte) : elle survit à l'acclamation
			local card = invite(c, 60)
			local before = expectClear(c, card, "640 × 360")
			c.HUD._onCheerPrompt({ heroId = 42, level = 3, expiresAt = c.Clock.now() + 10 })
			settleLayout(c, 1)
			local cheer = c.h.localPlayer.PlayerGui.HUD.Safe.Cheer
			expect(Layout.visible(cheer)).toBe(true)
			-- écran le plus serré : pas de place libre pendant l'acclamation, la carte peut passer
			-- sur l'état ou le suivi de quête (information), jamais sur un bouton
			expectClear(c, card, "640 × 360, ACCLAMER", { "Status", "QuestTracker" })
			-- acclamation finie : la carte revient à sa place libre
			settleLayout(c, 10)
			expect(Layout.visible(cheer)).toBe(false)
			local after = expectClear(c, card, "640 × 360, après ACCLAMER")
			expect(fmt(after)).toBe(fmt(before))
			finish(c)
		end)

		it("suivi de quête et état révélés pendant l'invitation : la carte se déplace", function()
			-- PC 1280 × 720, accueil Q1 : ni état ni suivi de quête au départ, la colonne de droite
			-- est libre sous la minicarte ; ils apparaissent pendant que la carte est affichée
			local c = boot(Vector2.new(1280, 720), 58, { step = 1, reveal = false })
			local hud = c.h.localPlayer.PlayerGui.HUD.Safe
			expect(c.HUD.isRevealed("questTracker")).toBe(false)
			expect(c.HUD.isRevealed("status")).toBe(false)
			local card = invite(c)
			local before = expectClear(c, card, "1280 × 720, colonne libre")
			c.HUD.reveal("questTracker", false)
			c.HUD.reveal("status", false)
			settleLayout(c, 2)
			expect(Layout.visible(hud.QuestTracker)).toBe(true)
			local after = expectClear(c, card, "1280 × 720, suivi et état affichés")
			expect(after.y0 ~= before.y0 or after.x0 ~= before.x0).toBe(true)
			finish(c)
		end)
	end)

	-- =============================================================================================
	-- ScreenFX : placeur du HUD et obstacles exposés aux cartes passagères
	-- =============================================================================================
	local function fxSetup()
		local h = Harness.new({ mode = "client" })
		h.localPlayer.LocaleId = "en-us"
		h:createRemotes()
		local c = {
			h = h,
			Root = h:require(CLIENT .. "UI.Root"),
			State = h:require(CLIENT .. "Controllers.StateController"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			FX = h:require(CLIENT .. "UI.ScreenFX"),
		}
		c.Root.Init()
		c.State.Init()
		c.Prefs.Init()
		c.FX.Init()
		return c
	end

	describe("Fix r5 ui-1 › ScreenFX.cardPlacement / hudObstacles", function()
		it("placeur absent, en erreur ou invalide : nil ; sinon sa réponse telle quelle", function()
			local c = fxSetup()
			expect(c.FX.cardPlacement(Vector2.new(360, 156), 0, 1)).toBeNil()
			local asked = nil
			c.FX.setCardPlacer(function(size, gap, wanted)
				asked = { size = size, gap = gap, wanted = wanted }
				return { right = 900, top = 120, count = 1 }
			end)
			expect(c.FX.cardPlacement(Vector2.new(360, 156), 0, 1)).toEqual({
				right = 900,
				top = 120,
				count = 1,
			})
			expect(asked.size).toEqual(Vector2.new(360, 156))
			expect(asked.wanted).toBe(1)
			-- entrées absurdes : le placeur n'est même pas appelé
			asked = nil
			expect(c.FX.cardPlacement("big", 0, 1)).toBeNil()
			expect(c.FX.cardPlacement(Vector2.new(0 / 0, 156), 0, 1)).toBeNil()
			expect(c.FX.cardPlacement(Vector2.new(360, 156), math.huge, 1)).toBeNil()
			expect(asked).toBeNil()
			c.FX.setCardPlacer(function()
				return { right = 0 / 0, top = 1, count = 1 }
			end)
			expect(c.FX.cardPlacement(Vector2.new(360, 156), 0, 1)).toBeNil()
			c.FX.setCardPlacer(function()
				error("boom")
			end)
			expect(c.FX.cardPlacement(Vector2.new(360, 156), 0, 1)).toBeNil()
			c.FX.setCardPlacer(function()
				return "junk"
			end)
			expect(c.FX.cardPlacement(Vector2.new(360, 156), 0, 1)).toBeNil()
			expect(table.concat(c.h.errors, "\n")).toBe("")
		end)

		it("obstacles : éléments affichés seulement ; Dash + Ping = coin jusqu'au bas droit", function()
			local c = fxSetup()
			expect(#c.FX.hudObstacles()).toBe(0)
			local g = c.h.globals
			local screen = g.Instance.new("ScreenGui")
			screen.Parent = c.h.localPlayer.PlayerGui
			local safe = g.Instance.new("Frame")
			safe.Name = "Safe"
			safe.Parent = screen
			local function element(name, pos, size, visible)
				local holder = g.Instance.new("Frame")
				holder.Name = name
				holder.Visible = visible ~= false
				holder.AbsolutePosition = pos
				holder.AbsoluteSize = size
				holder.Parent = safe
				local visual = g.Instance.new("TextButton")
				visual.AbsolutePosition = pos
				visual.AbsoluteSize = size
				visual.Parent = holder
				return visual
			end
			local visuals = {
				dash = element("Dash", Vector2.new(500, 300), Vector2.new(60, 60)),
				ping = element("Ping", Vector2.new(430, 320), Vector2.new(40, 40)),
				status = element("Status", Vector2.new(400, 100), Vector2.new(130, 40)),
				questTracker = element("QuestTracker", Vector2.new(100, 100), Vector2.new(80, 40), false),
			}
			c.FX.setAnchorResolver(function(name)
				if name == "minimap" then
					error("pas encore construite")
				end
				return visuals[name]
			end)
			local list = c.FX.hudObstacles()
			-- état (affiché) + coin des actions ; le suivi (caché) et la minicarte (erreur) ignorés
			expect(#list).toBe(2)
			-- état : bloc d'information (soft), qu'une carte peut couvrir faute de mieux
			expect(list[1]).toEqual({ x0 = 400, y0 = 100, x1 = 530, y1 = 140, soft = true })
			local corner = list[2]
			expect(corner.x0).toBe(430)
			expect(corner.y0).toBe(300)
			expect(corner.x1 > 1e5 and corner.y1 > 1e5).toBe(true)
			expect(table.concat(c.h.errors, "\n")).toBe("")
		end)
	end)
end
