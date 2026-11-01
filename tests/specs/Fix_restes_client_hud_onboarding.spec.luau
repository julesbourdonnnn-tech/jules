--!nocheck
-- Restes client « HUD et accueil » :
--   * Main.client : chaque require / Init / Start est isolé (xpcall + warn nommant le module) ; un
--     contrôleur en panne ne laisse plus l'écran de chargement à vie : ClientReady est posé dès
--     l'instantané du profil, même sans HUD (Q11)
--   * Hud/EventPill : la météo passe avant un boost de serveur long (Glow Party), qui laisse aussi
--     la place au compte à rebours d'un événement à moins de 60 s ; la Nuit d'Or garde sa place (Q17)
local roblox = require("@lune/roblox")
local Vector2 = roblox.Vector2

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local T0 = 1800000000 -- pile à :00:00 UTC (Comète à chaque :X0, météo :02:00-:04:30, :08:00…)

	local function anyLine(lines, ...)
		local needles = { ... }
		for _, line in lines do
			local all = true
			for _, needle in needles do
				if not string.find(line, needle, 1, true) then
					all = false
					break
				end
			end
			if all then
				return true
			end
		end
		return false
	end

	-- =========================================================================================
	-- Main.client : isolation des pannes au démarrage
	-- =========================================================================================

	local function clientWith(patch)
		local h = Harness.new({ mode = "client", touch = true })
		h:createRemotes()
		patch(h)
		local ok, err = pcall(function()
			h:boot()
		end)
		return h, ok, err
	end

	describe("Fix restes client HUD/accueil › démarrage du client isolé (Q11)", function()
		it(
			"un Start qui lève (LightingController) : les suivants démarrent, ClientReady au profil",
			function()
				local h, ok, err = clientWith(function(h)
					local Lighting = h:require(CLIENT .. "Controllers.LightingController")
					Lighting.Start = function()
						error("panne simulée de LightingController")
					end
				end)
				expect({ ok = ok, err = if ok then nil else tostring(err) }).toEqual({ ok = true })
				-- les modules suivants ont démarré (HUD, Minimap, accueil)
				expect(h.localPlayer.PlayerGui:FindFirstChild("HUD") ~= nil).toBe(true)
				expect(h.localPlayer.PlayerGui:FindFirstChild("Onboarding") ~= nil).toBe(true)
				expect(anyLine(h:warnings(), "LightingController", "Start", "panne simulée")).toBe(true)
				-- l'écran de chargement attend le profil
				expect(h.localPlayer:GetAttribute("ClientReady")).toBeNil()
				h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", { glow = 5 })
				h:settle(2)
				expect(h.localPlayer:GetAttribute("ClientReady")).toBe(true)
			end
		)

		it("HUD en panne (Init et Start lèvent) : ClientReady posé quand même à l'instantané", function()
			local h, ok = clientWith(function(h)
				local HUD = h:require(CLIENT .. "UI.HUD")
				HUD.Init = function()
					error("panne simulée de HUD.Init")
				end
				HUD.Start = function()
					error("panne simulée de HUD.Start")
				end
			end)
			expect(ok).toBe(true)
			expect(anyLine(h:warnings(), "HUD", "Init")).toBe(true)
			expect(anyLine(h:warnings(), "HUD", "Start")).toBe(true)
			-- OnboardingController (après le HUD) a quand même démarré
			local Onboarding = h:require(CLIENT .. "Controllers.OnboardingController")
			expect(Onboarding._state().hintFrame ~= nil).toBe(true)
			expect(h.localPlayer:GetAttribute("ClientReady")).toBeNil()
			h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", { glow = 5 })
			h:settle(2)
			expect(h.localPlayer:GetAttribute("ClientReady")).toBe(true)
		end)

		it("un module qui ne se charge pas (require lève) : signalé, les autres démarrent", function()
			local h, ok = clientWith(function(h)
				-- require du module en échec (même effet qu'une erreur au chargement du module)
				h.loading[h:find(CLIENT .. "Controllers.LightingController")] = true
			end)
			expect(ok).toBe(true)
			expect(anyLine(h:warnings(), "LightingController", "require")).toBe(true)
			h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", { glow = 5 })
			h:settle(2)
			expect(h.localPlayer:GetAttribute("ClientReady")).toBe(true)
		end)

		it(
			"démarrage sain : aucun avertissement, ClientReady au profil (une seule fois, booléen)",
			function()
				local h, ok = clientWith(function() end)
				expect(ok).toBe(true)
				local changes = 0
				h.localPlayer:GetAttributeChangedSignal("ClientReady"):Connect(function()
					changes += 1
				end)
				h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", { glow = 5 })
				h:settle(2)
				expect(h.localPlayer:GetAttribute("ClientReady")).toBe(true)
				expect(changes).toBe(1)
				expect(#h:warnings()).toBe(0)
			end
		)
	end)

	-- =========================================================================================
	-- Hud/EventPill : météo et prochain événement avant un boost long
	-- =========================================================================================

	local function pill()
		local h = Harness.new({ mode = "client" })
		local L = h:require("ReplicatedStorage.Shared.Localization")
		return {
			EventPill = h:require(CLIENT .. "UI.Hud.EventPill"),
			t = function(key, vars)
				return L.get("en", key, vars)
			end,
			nameOf = function()
				return nil
			end,
		}
	end

	local function events(now, over)
		local ev = { t = now, wisps = {} }
		for k, v in over do
			ev[k] = v
		end
		return ev
	end

	describe("Fix restes client HUD/accueil › pastille d'événement et boosts de serveur (Q17)", function()
		it("Glow Party (60 min en file) + fenêtre météo : la météo et son compte à rebours", function()
			local c = pill()
			local now = T0 + 150 -- :02:30, fenêtre météo :02:00-:04:30
			local ev = events(now, {
				weather = { key = "aurora", startsAt = T0 + 120, endsAt = T0 + 270 },
				serverBoost = { endsAt = now + 3552, source = "glowParty" },
			})
			local s = c.EventPill.compute(ev, now, c.t, c.nameOf)
			expect(s.kind).toBe("weather")
			expect(s.key).toBe("hud.event.weather")
			expect(s.vars.time).toBe("2:00")
			expect(s.active).toBe(true)
		end)

		it("Glow Party + Comète dans 45 s : le compte à rebours de la Comète", function()
			local c = pill()
			local now = T0 + 1155 -- :19:15 ; Comète à :20, prochaine météo à :22
			local ev = events(now, { serverBoost = { endsAt = now + 3000, source = "glowParty" } })
			local s = c.EventPill.compute(ev, now, c.t, c.nameOf)
			expect(s.kind).toBe("next")
			expect(s.key).toBe("hud.event.nextComet")
			expect(s.vars.time).toBe("0:45")
			-- pile 60 s avant : toujours le prochain événement
			s = c.EventPill.compute(ev, T0 + 1140, c.t, c.nameOf)
			expect(s.kind).toBe("next")
			expect(s.vars.time).toBe("1:00")
		end)

		it("Glow Party sans météo ni événement proche : le boost reste affiché", function()
			local c = pill()
			local now = T0 + 1095 -- :18:15 ; Comète dans 105 s
			local ev = events(now, { serverBoost = { endsAt = now + 600, source = "glowParty" } })
			local s = c.EventPill.compute(ev, now, c.t, c.nameOf)
			expect(s.kind).toBe("boost")
			expect(s.key).toBe("hud.event.glowParty")
			expect(s.vars.time).toBe("10:00")
			-- boost terminé : prochain événement
			s = c.EventPill.compute(ev, now + 600, c.t, c.nameOf)
			expect(s.kind).toBe("next")
			-- source inconnue : même règle que la Glow Party (clé de repli)
			ev.serverBoost = { endsAt = T0 + 1155 + 500, source = "mystery" }
			expect(c.EventPill.compute(ev, T0 + 1155, c.t, c.nameOf).kind).toBe("next")
			expect(c.EventPill.compute(ev, now, c.t, c.nameOf).kind).toBe("boost")
		end)

		it(
			"priorités inchangées : Comète, Balise, Frenzy, Starfall avant la météo et les boosts",
			function()
				local c = pill()
				local now = T0 + 150
				local base = {
					weather = { key = "aurora", startsAt = T0 + 120, endsAt = T0 + 270 },
					serverBoost = { endsAt = now + 3000, source = "glowParty" },
				}
				local ev = events(now, base)
				ev.frenzy = { endsAt = now + 30 }
				expect(c.EventPill.compute(ev, now, c.t, c.nameOf).kind).toBe("frenzy")
				ev.frenzy = nil
				ev.starfall = { startsAt = now - 10, endsAt = now + 500 }
				expect(c.EventPill.compute(ev, now, c.t, c.nameOf).kind).toBe("starfall")
				ev.starfall = nil
				ev.comet = {
					id = 1,
					phase = "ground",
					x = 0,
					z = 0,
					code = 1,
					warnAt = 0,
					impactAt = now,
					burstAt = now + 60,
				}
				expect(c.EventPill.compute(ev, now, c.t, c.nameOf).kind).toBe("comet")
			end
		)

		it("Nuit d'Or (temps fort de 5 min après la Balise) : garde sa place devant la météo", function()
			local c = pill()
			local now = T0 + 150
			local ev = events(now, {
				weather = { key = "aurora", startsAt = T0 + 120, endsAt = T0 + 270 },
				serverBoost = { endsAt = now + 200, source = "goldenNight" },
			})
			local s = c.EventPill.compute(ev, now, c.t, c.nameOf)
			expect(s.kind).toBe("boost")
			expect(s.key).toBe("hud.event.goldenNight")
			-- Nuit d'Or déclenchée par LiveOps : même règle
			ev.serverBoost = { endsAt = now + 200, source = "liveOps" }
			expect(c.EventPill.compute(ev, now, c.t, c.nameOf).key).toBe("hud.event.goldenNight")
			-- données incohérentes : jamais d'erreur
			ev.serverBoost = { endsAt = 0 / 0, source = "glowParty" }
			expect(c.EventPill.compute(ev, now, c.t, c.nameOf).kind).toBe("weather")
			ev.weather = nil
			expect(c.EventPill.compute(ev, now, c.t, c.nameOf).kind).toBe("next")
		end)
	end)

	-- =========================================================================================
	-- HUD : le rail de menus reste hors du quart inférieur (joystick dynamique) sur téléphone
	-- =========================================================================================

	local RAIL_NAMES = { "Upgrades", "Collection", "Goals", "Shop" }

	local function hudSetup()
		local h = Harness.new({ mode = "client", touch = true })
		h.localPlayer.LocaleId = "en-us"
		h:createRemotes()
		-- une boutique non vide (un id de passe renseigné) : l'icône Boutique fait partie du rail
		-- (avec tous les ids à 0, elle est masquée par conception : Model.shopHasItems)
		h:require("ReplicatedStorage.Shared.Config.Monetization").Passes.DoubleGlow.id = 1
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
		c.HUD.Init()
		c.FX.Start()
		c.Input.Start()
		c.HUD.Start()
		return c
	end

	local function hud(c)
		return c.h.localPlayer.PlayerGui.HUD.Safe
	end

	-- écran simulé (comme Fix_client-hud_r2) : AbsoluteSize = zone sous la barre Roblox, bouton de
	-- saut tactile de Roblox (70 px à (1, −95, 1, −90) sur petit écran)
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

	-- zone intérieure du HUD en px de référence (Safe ÷ échelle − marges 12/8 de Root.safe)
	local function content(c)
		local gui = c.h.localPlayer.PlayerGui.HUD
		local k = c.Root.scale()
		return gui.AbsoluteSize.X / k - 24, gui.AbsoluteSize.Y / k - 16
	end

	-- Rectangles des boutons AFFICHÉS du rail, placés comme le moteur le ferait d'après l'objet de
	-- mise en page du rail (UIGridLayout : FillDirectionMaxCells cellules par ligne, dans la
	-- largeur du rail ; UIListLayout vertical : une colonne)
	local function railRects(c)
		local rail = hud(c).Rail
		local grid = rail:FindFirstChildOfClass("UIGridLayout")
		local list = rail:FindFirstChildOfClass("UIListLayout")
		local cellW, cellH, padX, padY, perRow
		if grid then
			cellW, cellH = grid.CellSize.X.Offset, grid.CellSize.Y.Offset
			padX, padY = grid.CellPadding.X.Offset, grid.CellPadding.Y.Offset
			local fit = math.floor((rail.Size.X.Offset + padX) / (cellW + padX))
			perRow = math.max(1, math.min(grid.FillDirectionMaxCells, fit))
		else
			assert(list, "rail sans objet de mise en page")
			cellW, cellH, padX, padY, perRow = 80, 80, 0, list.Padding.Offset, 1
		end
		local shown = {}
		for _, name in RAIL_NAMES do
			if rail[name].Visible then
				table.insert(shown, rail[name])
			end
		end
		table.sort(shown, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		local out = {}
		for i, holder in shown do
			local col, row = (i - 1) % perRow, (i - 1) // perRow
			local x = rail.Position.X.Offset + col * (cellW + padX)
			local y = rail.Position.Y.Offset + row * (cellH + padY)
			out[holder.Name] = { x0 = x, y0 = y, x1 = x + cellW, y1 = y + cellH, index = i }
		end
		return out, perRow
	end

	local function checkRail(c, label)
		local W, H = content(c)
		local rects = railRects(c)
		local rail = hud(c).Rail
		for _, name in RAIL_NAMES do
			local r = rects[name]
			if r then
				-- bas du bouton au-dessus du quart inférieur (joystick dynamique, GDD §10.1)
				expect({ screen = label, button = name, clear = r.y1 <= 0.75 * H + 1e-6 }).toEqual({
					screen = label,
					button = name,
					clear = true,
				})
				-- sous la pastille Stardust (16, 88 ; 200 × 48), dans la moitié gauche, dans le rail
				expect({ screen = label, button = name, ok = r.y0 >= 88 + 48 + 8 - 1e-6 }).toEqual({
					screen = label,
					button = name,
					ok = true,
				})
				expect(r.x0 >= 16 and r.x1 <= W / 2).toBe(true)
				expect(r.x1 <= rail.Position.X.Offset + rail.Size.X.Offset + 1e-6).toBe(true)
				expect(r.y1 <= rail.Position.Y.Offset + rail.Size.Y.Offset + 1e-6).toBe(true)
			end
		end
		return rects
	end

	describe("Fix restes client HUD/accueil › rail hors de la zone du joystick (Q16, N51)", function()
		it("800 × 360 et 844 × 390 : chaque bouton du rail finit au-dessus du quart inférieur", function()
			local c = hudSetup()
			c.HUD.revealAll()
			for _, size in { { 800, 360, 36 }, { 800, 360, 58 }, { 844, 390, 36 }, { 844, 390, 58 } } do
				screen(c, size[1], size[2], size[3])
				local label = size[1] .. "x" .. size[2] .. "/" .. size[3]
				local rects = checkRail(c, label)
				for _, name in RAIL_NAMES do
					expect({ screen = label, button = name, shown = rects[name] ~= nil }).toEqual({
						screen = label,
						button = name,
						shown = true,
					})
				end
			end
		end)

		it("grille 2 × 2 dès y = 144 (boutons de 80, écart 8) et navigation manette recâblée", function()
			local c = hudSetup()
			c.HUD.revealAll()
			screen(c, 800, 360, 36)
			local rail = hud(c).Rail
			expect(rail.Position).toEqual(roblox.UDim2.fromOffset(16, 144))
			expect(rail.Size).toEqual(roblox.UDim2.fromOffset(168, 168))
			local rects, perRow = railRects(c)
			expect(perRow).toBe(2)
			expect(rects.Upgrades.y0).toBe(144)
			expect(rects.Shop.y1).toBe(312)
			for _, name in RAIL_NAMES do
				expect(rail[name].Size).toEqual(roblox.UDim2.fromOffset(80, 80))
			end
			local b = {}
			for _, name in RAIL_NAMES do
				b[name] = rail[name].Button
			end
			expect(b.Upgrades.NextSelectionRight).toBe(b.Collection)
			expect(b.Upgrades.NextSelectionDown).toBe(b.Goals)
			expect(b.Upgrades.NextSelectionLeft).toBeNil()
			expect(b.Upgrades.NextSelectionUp).toBeNil()
			expect(b.Collection.NextSelectionLeft).toBe(b.Upgrades)
			expect(b.Collection.NextSelectionDown).toBe(b.Shop)
			expect(b.Collection.NextSelectionRight).toBeNil()
			expect(b.Goals.NextSelectionUp).toBe(b.Upgrades)
			expect(b.Goals.NextSelectionRight).toBe(b.Shop)
			expect(b.Shop.NextSelectionUp).toBe(b.Collection)
			expect(b.Shop.NextSelectionLeft).toBe(b.Goals)
			expect(b.Shop.NextSelectionDown).toBeNil()
			-- écran haut (tablette, PC) : colonne du GDD (y 150 → 494), navigation verticale
			screen(c, 1280, 720, 36)
			expect(rail.Position).toEqual(roblox.UDim2.fromOffset(16, 150))
			expect(rail.Size).toEqual(roblox.UDim2.fromOffset(80, 344))
			local column = checkRail(c, "1280x720")
			expect(column.Shop.y1).toBe(494)
			expect(b.Upgrades.NextSelectionDown).toBe(b.Collection)
			expect(b.Collection.NextSelectionUp).toBe(b.Upgrades)
			expect(b.Goals.NextSelectionDown).toBe(b.Shop)
			expect(b.Upgrades.NextSelectionRight).toBeNil()
			expect(b.Goals.NextSelectionLeft).toBeNil()
			-- et retour au téléphone
			screen(c, 844, 390, 36)
			expect(rail.Size).toEqual(roblox.UDim2.fromOffset(168, 168))
			expect(b.Upgrades.NextSelectionRight).toBe(b.Collection)
		end)

		it(
			"révélation progressive (Améliorer puis Objectifs) : voisins parmi les boutons affichés",
			function()
				local c = hudSetup()
				screen(c, 800, 360, 36)
				c.HUD.reveal("rail.Upgrades", false)
				c.HUD.reveal("rail.Goals", false)
				local rail = hud(c).Rail
				local up, goals = rail.Upgrades.Button, rail.Goals.Button
				-- la grille tasse les boutons affichés : Objectifs à droite d'Améliorer
				local rects = checkRail(c, "accueil Q3")
				expect(rects.Goals.y0).toBe(rects.Upgrades.y0)
				expect(up.NextSelectionRight).toBe(goals)
				expect(goals.NextSelectionLeft).toBe(up)
				expect(up.NextSelectionDown).toBeNil()
				-- un bouton caché n'est jamais une cible de navigation
				expect(rail.Collection.Button.NextSelectionLeft).toBeNil()
				c.HUD.reveal("rail.Collection", false)
				expect(up.NextSelectionRight).toBe(rail.Collection.Button)
				expect(up.NextSelectionDown).toBe(goals)
				-- sélection manette (Y) : premier bouton affiché
				expect(c.HUD.selectRail()).toBe(true)
				expect(#c.h:signalErrors()).toBe(0)
			end
		)
	end)

	-- =========================================================================================
	-- OnboardingController : instruction hors des toasts, d'ACCLAMER et des panneaux
	-- =========================================================================================

	local Schema = Harness.new():require("ServerScriptService.Server.Data.Schema")
	local Vector3 = roblox.Vector3
	local CFrame = roblox.CFrame

	local function obSetup()
		local h = Harness.new({ mode = "client", touch = true })
		h.localPlayer.LocaleId = "en-us"
		h:createRemotes()
		h.game.GuiService.ReducedMotionEnabled = true
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = {
			h = h,
			g = h.globals,
			Clock = Clock,
			WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
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
			open = nil,
			page = nil,
		}
		-- isolation : paquets client-world et client-panels remplacés
		c.VFX.playDash = function() end
		c.WSC.localSlot = function()
			return 1
		end
		c.WSC.lineLength = function()
			return 0
		end
		c.WSC.wilds = function()
			return {}
		end
		c.Panels.open = function(name)
			if c.open == name then
				return
			end
			if c.open then
				c.Panels.Closed:Fire(c.open)
			end
			c.open = name
			c.Panels.Opened:Fire(name)
		end
		c.Panels.close = function()
			local name = c.open
			c.open = nil
			if name then
				c.Panels.Closed:Fire(name)
			end
		end
		c.Panels.current = function()
			return c.open
		end
		c.Panels.page = function()
			return c.page
		end
		c.h.localPlayer.Character.HumanoidRootPart.CFrame =
			CFrame.new(c.WorldLayout.gateCFrame(1).Position + Vector3.new(0, 3, 0))
		local order = { "Root", "State", "Prefs", "FX", "Input", "HUD", "Minimap", "Onboarding" }
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

	local function obLoad(c, over)
		local p = Schema.defaults()
		for k, v in over or {} do
			p[k] = v
		end
		c.h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", p)
		c.h:settle(1)
	end

	local function obRun(c, n)
		for _ = 1, n or 3 do
			c.h:step(1 / 30, 1)
			c.h:settle(1)
		end
	end

	local function hintOf(c)
		return c.h.localPlayer.PlayerGui.Onboarding.Safe.Hint
	end

	local function hintRect(c)
		local hint = hintOf(c)
		local W = content(c)
		local y = hint.Position.Y.Offset
		local w, hh = hint.Size.X.Offset, hint.Size.Y.Offset
		return { x0 = W / 2 - w / 2, y0 = y, x1 = W / 2 + w / 2, y1 = y + hh }
	end

	-- pile de toasts (UI/Toast) : rectangle des toasts affichés, d'après leur conteneur et sa liste
	local function toastRect(c)
		local stack = c.h.localPlayer.PlayerGui.Toasts.Safe.Stack
		local W = content(c)
		local padding = stack:FindFirstChildOfClass("UIListLayout").Padding.Offset
		local y, n, width = stack.Position.Y.Offset, 0, 0
		for _, toast in stack:GetChildren() do
			if toast.Name == "Toast" then
				y += toast.Size.Y.Offset + (if n > 0 then padding else 0)
				n += 1
				width = math.max(width, toast.Size.X.Offset)
			end
		end
		return { x0 = W / 2 - width / 2, y0 = stack.Position.Y.Offset, x1 = W / 2 + width / 2, y1 = y, n = n }
	end

	local function overlaps(a, b)
		return a.x0 < b.x1 and b.x0 < a.x1 and a.y0 < b.y1 and b.y0 < a.y1
	end

	describe(
		"Fix restes client HUD/accueil › instruction d'accueil lisible (Q18, N93, N154, N159, N163)",
		function()
			it(
				"téléphones et PC : l'instruction ne touche ni la pile de 3 toasts ni le compteur de file",
				function()
					local c = obSetup()
					obLoad(c, { onboarding = { step = 1, p = 0 } })
					obRun(c, 3)
					expect(c.Onboarding.currentHint()).toBe("onboarding.catch")
					for i = 1, 3 do
						c.Toast.show("Toast " .. i, "info")
					end
					for _, size in
						{
							{ 800, 360, 36 },
							{ 800, 360, 58 },
							{ 844, 390, 36 },
							{ 844, 390, 58 },
							{ 667, 375, 36 },
							{ 1280, 720, 36 },
						}
					do
						screen(c, size[1], size[2], size[3])
						obRun(c, 4)
						local label = size[1] .. "x" .. size[2] .. "/" .. size[3]
						local _, H = content(c)
						local hint, toasts = hintRect(c), toastRect(c)
						expect(toasts.n).toBe(3)
						expect({ screen = label, overlap = overlaps(hint, toasts) }).toEqual({
							screen = label,
							overlap = false,
						})
						-- compteur de file (bas centre, y = −24, 56 de haut) : écart d'au moins 8 px
						expect({ screen = label, clear = hint.y1 + 8 <= H - 24 - 56 + 1e-6 }).toEqual({
							screen = label,
							clear = true,
						})
						expect(hintOf(c).Visible).toBe(true)
						expect(c.h.localPlayer.PlayerGui.Onboarding.DisplayOrder).toBe(20)
						-- même règle que la colonne de droite du HUD (zone réservée)
						expect(hint.y0).toBe(c.HUD.hintTop())
					end
					expect(#c.h:signalErrors()).toBe(0)
				end
			)

			it(
				"Améliorer ouvert : « Buy Conga +1 » au-dessus de la fenêtre, ancrée sur son bord haut",
				function()
					local c = obSetup()
					screen(c, 800, 360, 36)
					obLoad(c, { onboarding = { step = 1, p = 0 }, stats = { parades = 1, catches = 3 } })
					obRun(c, 3)
					expect(c.Onboarding.currentHint()).toBe("onboarding.tapUpgrade")
					-- fenêtre des panneaux mesurée par le moteur : haut à 40 px réels sous la zone sûre
					local window = c.g.Instance.new("CanvasGroup")
					window.Name = "Window"
					window.AbsolutePosition = Vector2.new(50, 40)
					window.AbsoluteSize = Vector2.new(700, 280)
					local page = c.g.Instance.new("Frame")
					page.Name = "Page_Upgrades"
					page.Parent = window
					c.page = page
					c.Panels.open("Upgrades")
					obRun(c, 3)
					expect(c.Onboarding.currentHint()).toBe("onboarding.buyConga")
					local hint = hintOf(c)
					expect(hint.Visible).toBe(true)
					expect(hint.GroupTransparency).toBe(0)
					expect(c.Onboarding._state().hintShown).toBe(true)
					expect(c.Onboarding._state().hintDocked).toBe(true)
					-- au-dessus de la fenêtre des panneaux (DisplayOrder 30)
					local panelsOrder = 30
					expect(c.h.localPlayer.PlayerGui.Onboarding.DisplayOrder > panelsOrder).toBe(true)
					expect(c.h.localPlayer.PlayerGui.Onboarding.DisplayOrder < 40).toBe(true) -- sous les bannières
					-- à cheval sur le bord haut de la fenêtre (40 / 0,6 − 8 ≈ 58,7 px de référence)
					local top = 40 / c.Root.scale() - 8
					local r = hintRect(c)
					expect(r.y0 < top and r.y1 > top).toBe(true)
					expect(r.y0 >= 8).toBe(true)
					-- fenêtre pas encore mesurée : en haut de l'écran, toujours au-dessus du panneau
					c.page = nil
					obRun(c, 4)
					expect(hint.Position.Y.Offset).toBe(8)
					expect(hint.Visible).toBe(true)
					-- fermeture : place normale sous les toasts, écran d'accueil redescendu
					c.Panels.close()
					obRun(c, 3)
					expect(c.Onboarding.currentHint()).toBe("onboarding.tapUpgrade")
					expect(hint.Visible).toBe(true)
					expect(hint.Position.Y.Offset).toBe(c.HUD.hintTop())
					expect(c.h.localPlayer.PlayerGui.Onboarding.DisplayOrder).toBe(20)
					expect(#c.h:signalErrors()).toBe(0)
				end
			)

			it(
				"autre panneau ouvert : l'instruction (sans rapport) s'efface puis revient à la fermeture",
				function()
					local c = obSetup()
					screen(c, 844, 390, 36)
					obLoad(c, { onboarding = { step = 1, p = 0 } })
					obRun(c, 3)
					expect(c.Onboarding.currentHint()).toBe("onboarding.catch")
					local hint = hintOf(c)
					expect(hint.Visible).toBe(true)
					c.Panels.open("Goals")
					obRun(c, 3)
					-- même instruction, volontairement effacée (elle serait sous la fenêtre)
					expect(c.Onboarding.currentHint()).toBe("onboarding.catch")
					expect(c.Onboarding._state().hintShown).toBe(false)
					expect(hint.Visible).toBe(false)
					expect(c.h.localPlayer.PlayerGui.Onboarding.DisplayOrder).toBe(20)
					c.Panels.close()
					obRun(c, 3)
					expect(hint.Visible).toBe(true)
					expect(hint.GroupTransparency).toBe(0)
					expect(#c.h:signalErrors()).toBe(0)
				end
			)

			it("ACCLAMER sur téléphone : l'instruction s'efface 10 s ; écran haut : elle reste", function()
				local c = obSetup()
				screen(c, 800, 360, 36)
				obLoad(c, { onboarding = { step = 1, p = 0 } })
				obRun(c, 3)
				local hint = hintOf(c)
				expect(hint.Visible).toBe(true)
				c.HUD._onCheerPrompt({ heroId = 2, level = 1, expiresAt = T0 + 10 })
				obRun(c, 4)
				expect(c.HUD.cheerOverHint()).toBe(true)
				expect(hint.Visible).toBe(false)
				-- l'acclamation expire : l'instruction revient
				c.Clock.freeze(T0 + 11)
				obRun(c, 8) -- replacement toutes les 0,1 s
				expect(c.HUD.cheerOverHint()).toBe(false)
				expect(hint.Visible).toBe(true)
				-- PC 1280 × 720 : ACCLAMER (y ≥ 480) ne touche pas l'instruction (y 342-398)
				screen(c, 1280, 720, 36)
				c.HUD._onCheerPrompt({ heroId = 2, level = 1, expiresAt = T0 + 20 })
				obRun(c, 4)
				expect(c.HUD.cheerOverHint()).toBe(false)
				expect(hint.Visible).toBe(true)
				expect(#c.h:signalErrors()).toBe(0)
			end)
		end
	)

	-- =========================================================================================
	-- ScreenFX : le tampon de Starforge ne gâche plus la révélation du panneau Collection
	-- =========================================================================================

	describe(
		"Fix restes client HUD/accueil › Starforge : révélation laissée au panneau (N53)",
		function()
			local function smallStamp(c)
				local stamp = c.h.localPlayer.PlayerGui.ScreenFX.Safe:FindFirstChild("SmallStamp")
				return if stamp and stamp.Visible then stamp.Text else nil
			end

			it(
				"Collection ouverte : aucun tampon d'écran, le panneau reçoit toujours Celebrated",
				function()
					local c = hudSetup()
					local open = "Collection"
					c.Panels.current = function()
						return open
					end
					local seen = {}
					c.FX.Celebrated:Connect(function(payload)
						table.insert(seen, payload.kind)
					end)
					local payload =
						{ kind = "starforge", data = { uid = "n1", s = 1, f = 0, v = 0, stars = 3 } }
					c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", payload)
					c.h:settle(1)
					expect(smallStamp(c)).toBeNil()
					expect(seen[1]).toBe("starforge")
					-- panneau fermé (Starforge terminé ailleurs, ex. « Tout fusionner » puis fermeture) : tampon
					open = nil
					c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", payload)
					c.h:settle(1)
					expect(smallStamp(c)).toBe("★3!")
					-- autre panneau ouvert : le tampon reste (aucune autre révélation à l'écran)
					c.h:step(1 / 10, 40)
					expect(smallStamp(c)).toBeNil()
					open = "Upgrades"
					c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", payload)
					c.h:settle(1)
					expect(smallStamp(c)).toBe("★3!")
					expect(#seen).toBe(3)
					expect(#c.h:signalErrors()).toBe(0)
				end
			)

			it("crochet absent ou en erreur : comportement d'origine, jamais d'erreur", function()
				local c = hudSetup()
				c.FX.setPanelResolver(function()
					error("panne du crochet")
				end)
				local payload = { kind = "starforge", data = { stars = 2 } }
				c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", payload)
				c.h:settle(1)
				expect(smallStamp(c)).toBe("★2!")
				c.FX.setPanelResolver(nil)
				c.h:step(1 / 10, 40)
				c.h:fireClient(
					"ReplicatedStorage.Remotes.Celebrate",
					{ kind = "starforge", data = { stars = 4 } }
				)
				c.h:settle(1)
				expect(smallStamp(c)).toBe("★4!")
				expect(#c.h:signalErrors()).toBe(0)
			end)
		end
	)
end
