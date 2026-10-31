--!nocheck
-- HUD (paquet client-hud) : construction et affichage progressif (reveal / revealAll / attention /
-- anchor), ClientReady, Glow prédit (Hud/Glow) et compteurs qui défilent (Hud/Counter), compteur de
-- file, Dash (balayage radial, placement près du bouton de saut tactile), pastille d'événement
-- (Hud/EventPill), indicateurs d'état, suivi de quête, rail et pastilles « ! », bouton ACCLAMER
-- (remote CheerPrompt / Cheer), langue, charges malveillantes (docs §13.12, GDD §3, §9.2, §10.2).
local roblox = require("@lune/roblox")
local Vector2 = roblox.Vector2
local UDim2 = roblox.UDim2

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local T0 = 1800000000

	local function setup(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", touch = opts.touch })
		h.localPlayer.LocaleId = opts.locale or "en-us"
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = {
			h = h,
			g = h.globals,
			Clock = Clock,
			Formulas = h:require("ReplicatedStorage.Shared.Logic.Formulas"),
			EventClock = h:require("ReplicatedStorage.Shared.Logic.EventClock"),
			Format = h:require("ReplicatedStorage.Shared.Util.Format"),
			L = h:require("ReplicatedStorage.Shared.Localization"),
			Root = h:require(CLIENT .. "UI.Root"),
			State = h:require(CLIENT .. "Controllers.StateController"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			WSC = h:require(CLIENT .. "Controllers.WorldStateController"),
			VFX = h:require(CLIENT .. "Controllers.VFXController"),
			Panels = h:require(CLIENT .. "Controllers.PanelController"),
			FX = h:require(CLIENT .. "UI.ScreenFX"),
			Input = h:require(CLIENT .. "Controllers.InputController"),
			HUD = h:require(CLIENT .. "UI.HUD"),
			Glow = h:require(CLIENT .. "UI.Hud.Glow"),
			Counter = h:require(CLIENT .. "UI.Hud.Counter"),
			EventPill = h:require(CLIENT .. "UI.Hud.EventPill"),
			slot = 1,
			length = 0,
			events = nil,
			panelCalls = {},
			open = nil,
		}
		-- isolation : paquets client-world et client-panels remplacés
		c.VFX.playDash = function() end
		c.VFX.playUpgrade = function() end
		c.WSC.localSlot = function()
			return c.slot
		end
		c.WSC.lineLength = function()
			return c.length
		end
		c.WSC.events = function()
			return c.events
		end
		c.Panels.open = function(name, args)
			table.insert(c.panelCalls, { name = name, args = args })
			c.open = name
		end
		c.Panels.close = function()
			c.open = nil
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

	-- schéma chargé une fois, AVANT les harnais clients (Harness.new redirige les journaux réseau)
	local Schema = Harness.new():require("ServerScriptService.Server.Data.Schema")

	local function snapshot(c, data)
		local profile = Schema.defaults()
		for k, v in data or {} do
			profile[k] = v
		end
		c.h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", profile)
		c.h:settle(1)
	end

	local function hud(c)
		return c.h.localPlayer.PlayerGui.HUD.Safe
	end

	local function frames(c, n, dt)
		c.h:step(dt or 1 / 30, n)
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

	describe("HUD › construction et affichage progressif", function()
		it("tout est caché au départ ; ClientReady posé à la réception du profil", function()
			local c = setup()
			local gui = c.h.localPlayer.PlayerGui.HUD
			expect(gui.ResetOnSpawn).toBe(false)
			expect(hud(c).Glow.Visible).toBe(false)
			expect(hud(c).LineCounter.Visible).toBe(false)
			expect(hud(c).Dash.Visible).toBe(false)
			expect(c.h.localPlayer:GetAttribute("ClientReady")).toBeNil()
			snapshot(c)
			expect(c.h.localPlayer:GetAttribute("ClientReady")).toBe(true)
		end)

		it("reveal animé, idempotent ; rail.X affiche le rail ; anchor et isRevealed", function()
			local c = setup()
			c.HUD.reveal("glow", true)
			expect(hud(c).Glow.Visible).toBe(true)
			expect(c.HUD.isRevealed("glow")).toBe(true)
			expect(hud(c).Glow.HudScale.Scale).toBe(1) -- tween appliqué (harnais)
			c.HUD.reveal("glow", true)
			expect(c.HUD.isRevealed("stardust")).toBe(false)
			c.HUD.reveal("rail.Upgrades", true)
			expect(c.HUD.isRevealed("rail")).toBe(true)
			expect(hud(c).Rail.Visible).toBe(true)
			expect(hud(c).Rail.Upgrades.Visible).toBe(true)
			expect(hud(c).Rail.Collection.Visible).toBe(false)
			expect(c.HUD.anchor("glow")).toBe(hud(c).Glow.Pill)
			expect(c.HUD.anchor("nope")).toBeNil()
			-- un élément enregistré plus tard (minicarte) garde son état
			expect(c.HUD.isRevealed("minimap")).toBe(false)
			c.HUD.reveal("minimap", false)
			expect(c.HUD.isRevealed("minimap")).toBe(true)
			local frame = c.g.Instance.new("Frame")
			c.HUD.registerElement("minimap", frame)
			expect(frame.Visible).toBe(true)
			c.HUD.revealAll()
			for _, element in
				{
					"stardust",
					"line",
					"dash",
					"ping",
					"rail.Shop",
					"eventPill",
					"status",
					"questTracker",
					"crew",
					"settings",
				}
			do
				expect({ element = element, shown = c.HUD.isRevealed(element) }).toEqual({
					element = element,
					shown = true,
				})
			end
		end)

		it("attention : pulsation 1 → 1,08 et main sur l'icône Améliorer ; false arrête", function()
			local c = setup()
			c.HUD.reveal("rail.Upgrades", false)
			c.HUD.attention("rail.Upgrades", true)
			local scale = hud(c).Rail.Upgrades.HudScale
			local seen = {}
			for _ = 1, 12 do
				frames(c, 1, 0.07)
				table.insert(seen, scale.Scale)
			end
			local lo, hi = math.huge, -math.huge
			for _, v in seen do
				lo = math.min(lo, v)
				hi = math.max(hi, v)
			end
			expect(lo >= 1 - 1e-6 and hi <= 1.08 + 1e-6).toBe(true)
			expect(hi - lo > 0.03).toBe(true)
			expect(hud(c).Hand.Visible).toBe(true)
			c.HUD.attention("rail.Upgrades", false)
			frames(c, 1)
			expect(scale.Scale).toBe(1)
			expect(hud(c).Hand.Visible).toBe(false)
			-- Mouvement réduit : pas de pulsation
			c.Prefs._onSettings({ reducedMotion = true })
			c.HUD.attention("rail.Upgrades", true)
			frames(c, 5, 0.07)
			expect(scale.Scale).toBe(1)
		end)

		it("raccourcis gardés : pas de panneau dont l'icône est cachée ; rail → panneau", function()
			local c = setup()
			c.Input.togglePanel("Upgrades")
			expect(#c.panelCalls).toBe(0)
			c.HUD.reveal("rail.Upgrades", false)
			hud(c).Rail.Upgrades.Button.Activated:Fire()
			c.h:settle(1)
			expect(c.panelCalls[1].name).toBe("Upgrades")
			-- pastille « ! » pilotée par PanelController.BadgeChanged
			local badge = hud(c).Rail.Upgrades.Button.Badge
			expect(badge.Visible).toBe(false)
			c.Panels.BadgeChanged:Fire("Upgrades", true)
			expect(badge.Visible).toBe(true)
			c.Panels.BadgeChanged:Fire("Nope", true)
		end)
	end)

	describe("HUD › Glow prédit et compteurs", function()
		it("Glow.predict : revenu passif, retenue, bornes", function()
			local c = setup()
			local G = c.Glow
			expect(G.predict(100, 0.5, 3, T0, T0 + 10)).toBe(130)
			expect(G.predict(100, 0.5, 0, T0, T0 + 10)).toBe(100)
			expect(G.predict(100, 0, 3, 0, T0)).toBe(100) -- jamais réglé : pas d'extrapolation
			expect(G.predict(100, 0, 3, T0, T0 - 50)).toBe(100) -- horloge en arrière : ≥ serveur
			expect(G.predict(100, 0, 1, T0, T0 + 1e9)).toBe(100 + G.MAX_SECONDS) -- instantané périmé
			expect(G.predict(0 / 0, 0 / 0, math.huge, T0, T0 + 1)).toBe(0)
		end)

		it(
			"dérive du revenu passif sans pop ; gain discret : défilement 0,5 s + pop ; « +3/s »",
			function()
				local c = setup()
				snapshot(c, { glow = 100, glowCarry = 0.5, idleRate = 3, lastSettle = T0 })
				c.HUD.reveal("glow", false)
				frames(c, 2)
				local pill = hud(c).Glow.Pill
				expect(pill.Value.Text).toBe("100")
				expect(pill.Rate.Text).toBe("+3/s")
				c.Clock.advance(10)
				frames(c, 2)
				expect(pill.Value.Text).toBe("130")
				expect(pill:FindFirstChild("JuiceScale")).toBeNil()
				-- parade : +500 (patch serveur, règlement au même instant)
				c.h:fireClient(
					"ReplicatedStorage.Remotes.DataPatch",
					{ glow = 630, glowCarry = 0.5, lastSettle = T0 + 10 },
					{}
				)
				frames(c, 2, 0.05)
				local mid = tonumber((string.gsub(pill.Value.Text, ",", "")))
				expect(mid > 130 and mid < 630).toBe(true)
				expect(pill:FindFirstChild("JuiceScale") ~= nil).toBe(true)
				frames(c, 12, 0.05)
				expect(pill.Value.Text).toBe("630")
				-- dépense : défilement vers le bas
				c.h:fireClient("ReplicatedStorage.Remotes.DataPatch", { glow = 30 }, {})
				frames(c, 12, 0.05)
				expect(pill.Value.Text).toBe("30")
			end
		)

		it("Counter : Quint Out sur 0,5 s, cible mobile, format", function()
			local c = setup()
			local label = c.g.Instance.new("TextLabel")
			local pops = 0
			local counter = c.Counter.new(label, function(n)
				return "#" .. n
			end, 0)
			counter.onPop = function()
				pops += 1
			end
			expect(label.Text).toBe("#0")
			counter:set(1000, 0, true)
			expect(pops).toBe(1)
			counter:step(0.1)
			local early = tonumber(string.sub(label.Text, 2))
			expect(early > 500).toBe(true) -- Quint Out : l'essentiel au début
			counter:set(1100, 0.2, false) -- la cible continue d'avancer
			counter:step(0.5)
			expect(label.Text).toBe("#1100")
			counter:set(0 / 0, 0.6, true)
			counter:step(0.7)
			expect(label.Text).toBe("#1100")
		end)

		it("Stardust : pop à la hausse", function()
			local c = setup()
			snapshot(c, { stardust = 40 })
			c.HUD.reveal("stardust", false)
			frames(c, 2)
			local pill = hud(c).Stardust.Pill
			expect(pill.Value.Text).toBe("40")
			c.h:fireClient("ReplicatedStorage.Remotes.DataPatch", { stardust = 140 }, {})
			frames(c, 15, 0.05)
			expect(pill.Value.Text).toBe("140")
			expect(pill:FindFirstChild("JuiceScale") ~= nil).toBe(true)
		end)
	end)

	describe("HUD › compteur de file", function()
		it("vide, « 3/5 », Conga Bonus, barre ; pop à la capture ; français", function()
			local c = setup()
			snapshot(c, { upgrades = { conga = 2, stride = 0, lure = 0, perches = 0, guard = 0 } })
			local line = hud(c).LineCounter.Pill
			expect(line.Empty.Visible).toBe(true)
			expect(line.Empty.Text).toBe("Catch Nebbies!")
			expect(line.Count.Visible).toBe(false)
			c.length = 3
			c.WSC.LineOp:Fire(1, { op = "add", slot = 1, ver = 1, codes = { 1, 1, 1 }, ids = { 0, 0, 0 } })
			expect(line.Empty.Visible).toBe(false)
			expect(line.Count.Text).toBe("3/5")
			expect(line.Bonus.Text).toBe("×1.16")
			expect(line.Bar.Fill.Size).toEqual(UDim2.fromScale(0.6, 1))
			expect(line:FindFirstChild("JuiceScale") ~= nil).toBe(true)
			-- une capture d'un autre joueur ne change rien
			c.length = 0
			c.WSC.LineOp:Fire(4, { op = "add", slot = 4, ver = 1, codes = { 1 }, ids = { 0 } })
			expect(line.Count.Text).toBe("3/5")
			c.length = 3
			c.Prefs._onSettings({ lang = "fr" })
			c.h:settle(1)
			expect(line.Bonus.Text).toBe("×1,16")
			expect(line.Empty.Text).toBe(c.L.get("fr", "hud.line.empty"))
		end)

		it(
			"file pleine (Feedback lineFull) : 2 clignotements rouges en 0,3 s et flèche vers le Nid 2 s",
			function()
				local c = setup()
				snapshot(c)
				local holder = hud(c).LineCounter
				local stroke = holder.Pill:FindFirstChildOfClass("UIStroke")
				c.h:fireClient(
					"ReplicatedStorage.Remotes.Feedback",
					{ key = "feedback.lineFull", vars = {}, tone = "warning" }
				)
				frames(c, 1, 0.01)
				local danger = c.h:require(CLIENT .. "UI.Theme").Colors.Danger
				expect(stroke.Color).toBe(danger)
				expect(holder.NestArrow.Visible).toBe(true)
				frames(c, 10, 0.05)
				expect(stroke.Color ~= danger).toBe(true)
				frames(c, 40, 0.05)
				expect(holder.NestArrow.Visible).toBe(false)
			end
		)
	end)

	describe("HUD › Dash", function()
		it("appui : Dash envoyé, balayage radial pendant la recharge, pop au retour", function()
			local c = setup()
			snapshot(c)
			c.HUD.reveal("dash", false)
			local button = hud(c).Dash.Button
			button.Activated:Fire()
			c.h:settle(1)
			expect(#sent(c, "Dash")).toBe(1)
			frames(c, 1)
			expect(button.Cooldown.Right.Visible).toBe(true)
			expect(button.Cooldown.Left.Visible).toBe(true)
			c.Clock.advance(c.Formulas.dashCooldown(0) * 0.75)
			frames(c, 1)
			expect(button.Cooldown.Left.Visible).toBe(false) -- reste 25 %
			c.Clock.advance(c.Formulas.dashCooldown(0))
			frames(c, 1)
			expect(button.Cooldown.Right.Visible).toBe(false)
			-- refus pendant la recharge : le bouton tremble, rien n'est envoyé
			button.Activated:Fire()
			button.Activated:Fire()
			c.h:settle(1)
			expect(#sent(c, "Dash")).toBe(2)
		end)

		it(
			"tactile : coin bas droit du Dash au coin haut gauche du bouton de saut − 16 px ; PC : bas droite",
			function()
				local c = setup({ touch = true })
				local holder = hud(c).Dash
				c.HUD._layoutActions()
				expect(holder.Position).toEqual(UDim2.new(1, -170, 1, -130)) -- repli sans bouton de saut
				local touchGui = c.g.Instance.new("ScreenGui")
				touchGui.Name = "TouchGui"
				local frame = c.g.Instance.new("Frame")
				frame.Name = "TouchControlFrame"
				frame.Parent = touchGui
				local jump = c.g.Instance.new("ImageButton")
				jump.Name = "JumpButton"
				jump.AbsolutePosition = Vector2.new(1100, 560)
				jump.AbsoluteSize = Vector2.new(100, 100)
				jump.Parent = frame
				touchGui.Parent = c.h.localPlayer.PlayerGui
				c.HUD._layoutActions()
				local k = c.Root.scale()
				local origin = hud(c).AbsolutePosition
				local padding = hud(c):FindFirstChildOfClass("UIPadding")
				local inset = Vector2.new(padding.PaddingLeft.Offset, padding.PaddingTop.Offset)
				local expected = (Vector2.new(1100, 560) - origin) / k - inset - Vector2.new(16, 16)
				expect(holder.Position).toEqual(UDim2.fromOffset(expected.X, expected.Y))
				expect(hud(c).Ping.Position).toEqual(holder.Position + UDim2.fromOffset(-112 - 12, 0))
				-- passage au clavier : bas droite
				c.h.game.UserInputService.LastInputTypeChanged:Fire(roblox.Enum.UserInputType.Keyboard)
				c.h:settle(1)
				expect(holder.Position).toEqual(UDim2.new(1, -16, 1, -16))
				expect(hud(c).Dash.Button.KeyCap.Visible).toBe(true)
				expect(hud(c).Dash.Button.KeyCap.Text).toBe("E")
			end
		)
	end)

	describe("HUD › pastille d'événement", function()
		it(
			"prochain événement (gris), Comète portée « ☄ COMET 0:45 — Mira », barre de la Balise",
			function()
				local c = setup()
				c.HUD.reveal("eventPill", false)
				frames(c, 7)
				local pill = hud(c).EventPill
				local nextEvent = c.EventClock.nextEvent(T0)
				expect(pill.Pill.Text.Text).toContain(c.Format.clock(math.ceil(nextEvent.at - T0)))
				local mira = c.h:addPlayer({ userId = 2, name = "Mira" })
				expect(mira.DisplayName).toBe("Mira")
				c.events = {
					t = T0,
					comet = {
						id = 600,
						phase = "carried",
						x = 0,
						z = 0,
						code = 1,
						warnAt = T0 - 40,
						impactAt = T0 - 30,
						burstAt = T0 + 45,
						carrierId = 2,
					},
					wisps = {},
				}
				frames(c, 7)
				expect(pill.Pill.Text.Text).toBe("☄ COMET 0:45 — Mira")
				expect(pill.BeaconBar.Visible).toBe(false)
				c.events = {
					t = T0,
					beacon = {
						phase = "active",
						warnAt = T0 - 20,
						startsAt = T0 - 5,
						endsAt = T0 + 175,
						points = 12,
						goal = 40,
					},
					wisps = {},
				}
				frames(c, 7)
				expect(pill.Pill.Text.Text).toBe("Beacon Night · 2:55")
				expect(pill.BeaconBar.Visible).toBe(true)
				expect(pill.BeaconBar.Text.Text).toBe("12/40")
				expect(pill.BeaconBar.Fill.Size).toEqual(UDim2.fromScale(0.3, 1))
			end
		)

		it("EventPill.compute : priorités, météo, boost, données incohérentes", function()
			local c = setup()
			local t = function(key, vars)
				return c.L.get("en", key, vars)
			end
			local nameOf = function()
				return nil
			end
			local both = {
				t = T0,
				comet = {
					id = 1,
					phase = "ground",
					x = 0,
					z = 0,
					code = 1,
					warnAt = 0,
					impactAt = T0,
					burstAt = T0 + 60,
				},
				beacon = {
					phase = "active",
					warnAt = 0,
					startsAt = T0,
					endsAt = T0 + 100,
					points = 0,
					goal = 10,
				},
				weather = { key = "aurora", startsAt = T0 - 10, endsAt = T0 + 90 },
				wisps = {},
			}
			local s = c.EventPill.compute(both, T0, t, nameOf)
			expect(s.kind).toBe("comet")
			expect(s.key).toBe("hud.event.cometGround")
			both.comet = nil
			expect(c.EventPill.compute(both, T0, t, nameOf).kind).toBe("beacon")
			both.beacon = nil
			s = c.EventPill.compute(both, T0, t, nameOf)
			expect(s.kind).toBe("weather")
			expect(s.vars.weather).toBe("Aurora Drift")
			both.serverBoost = { endsAt = T0 + 300, source = "goldenNight" }
			expect(c.EventPill.compute(both, T0, t, nameOf).key).toBe("hud.event.goldenNight")
			both.serverBoost = nil
			both.weather = { key = "nope", startsAt = T0 - 10, endsAt = T0 + 90 }
			s = c.EventPill.compute(both, T0, t, nameOf)
			expect(s.kind).toBe("next")
			expect(s.active).toBe(false)
			-- Comète portée par un inconnu : « ? »
			both.comet = {
				id = 1,
				phase = "carried",
				x = 0,
				z = 0,
				code = 1,
				warnAt = 0,
				impactAt = T0,
				burstAt = T0 + 5,
				carrierId = 0 / 0,
			}
			expect(c.EventPill.compute(both, T0, t, nameOf).vars.name).toBe("?")
		end)
	end)

	describe("HUD › état, suivi de quête", function()
		it("bouclier près de la file, Zen, boost ×2 avec minuteur, connexion instable", function()
			local c = setup()
			snapshot(c, { boosts = { personalUntil = T0 + 90 } })
			c.HUD.reveal("status", false)
			local player = c.h.localPlayer
			player:SetAttribute("Rookie", true)
			player:SetAttribute("Unstable", true)
			c.h:settle(1)
			frames(c, 7)
			local status = hud(c).Status
			expect(hud(c).LineCounter.Shield.Visible).toBe(true)
			expect(status.Row.Rookie.Visible).toBe(true)
			expect(status.Row.Boost.Visible).toBe(true)
			expect(status.Row.Boost.Time.Text).toBe("1:30")
			expect(status.Row.Unstable.Visible).toBe(true)
			expect(status.Caption.Visible).toBe(true)
			expect(status.Caption.Text).toBe("Unstable connection")
			expect(status.Row.Zen.Visible).toBe(false)
			c.Prefs._onSettings({ zen = true })
			player:SetAttribute("Unstable", false)
			player:SetAttribute("Rookie", false)
			c.Clock.advance(100)
			frames(c, 7)
			expect(status.Row.Zen.Visible).toBe(true)
			expect(status.Row.Boost.Visible).toBe(false)
			expect(status.Row.Unstable.Visible).toBe(false)
			expect(hud(c).LineCounter.Shield.Visible).toBe(false)
			expect(status.Row.Rookie.Visible).toBe(false)
		end)

		it(
			"suivi de quête : quête d'accueil avec barre, puis objectif long Supernova ; repliable",
			function()
				local c = setup()
				snapshot(c, { onboarding = { step = 1, p = 2 } })
				c.HUD.reveal("questTracker", false)
				frames(c, 7)
				local pill = hud(c).QuestTracker.Pill
				expect(pill.Title.Text).toBe("Parade of 4")
				expect(pill.Bar.Fill.Size).toEqual(UDim2.fromScale(0.5, 1))
				c.h:fireClient(
					"ReplicatedStorage.Remotes.DataPatch",
					{ onboarding = { step = 8, p = 0 }, glow = 100000 },
					{}
				)
				frames(c, 7)
				expect(pill.Title.Text).toBe("Supernova · 400,000")
				expect(pill.Bar.Fill.Size).toEqual(UDim2.fromScale(0.25, 1))
				pill.Toggle.Button.Activated:Fire()
				c.h:settle(1)
				expect(pill.Title.Visible).toBe(false)
				pill.Toggle.Button.Activated:Fire()
				c.h:settle(1)
				expect(pill.Title.Visible).toBe(true)
			end
		)
	end)

	describe("HUD › acclamation (CheerPrompt)", function()
		it("le bouton monte, l'anneau décompte, l'appui envoie Cheer(heroId) une seule fois", function()
			local c = setup()
			snapshot(c)
			c.h:addPlayer({ userId = 2, name = "Lea" })
			c.h:fireClient(
				"ReplicatedStorage.Remotes.CheerPrompt",
				{ heroId = 2, level = 3, expiresAt = T0 + 10 }
			)
			local cheer = hud(c).Cheer
			expect(cheer.Visible).toBe(true)
			expect(cheer.Button.Title.Text).toBe("CHEER!")
			expect(cheer.Button.Hero.Text).toBe("Lea · SUPERNOVA III")
			c.Clock.advance(5)
			frames(c, 1)
			expect(cheer.Button.Ring.Time.Left.Visible).toBe(false) -- moitié écoulée
			cheer.Button.Activated:Fire()
			c.h:settle(2)
			expect(sent(c, "Cheer")[1][1]).toBe(2)
			c.Input.requestCheer()
			c.h:settle(2)
			expect(#sent(c, "Cheer")).toBe(1)
			expect(cheer.Visible).toBe(false)
		end)

		it("expiration : le bouton disparaît, F ne fait plus rien", function()
			local c = setup()
			snapshot(c)
			c.h:fireClient(
				"ReplicatedStorage.Remotes.CheerPrompt",
				{ heroId = 2, level = 1, expiresAt = T0 + 10 }
			)
			c.Clock.advance(11)
			frames(c, 2)
			c.h:settle(2)
			expect(hud(c).Cheer.Visible).toBe(false)
			expect(c.Input.requestCheer()).toBe(false)
			expect(#sent(c, "Cheer")).toBe(0)
		end)

		it("charges malveillantes ignorées (soi-même, NaN, expirée, lointaine, mauvais types)", function()
			local c = setup()
			snapshot(c)
			local me = c.h.localPlayer.UserId
			for _, payload in
				{
					"x",
					{},
					{ heroId = me, level = 1, expiresAt = T0 + 10 },
					{ heroId = 0 / 0, level = 1, expiresAt = T0 + 10 },
					{ heroId = 2.5, level = 1, expiresAt = T0 + 10 },
					{ heroId = 2, level = 0, expiresAt = T0 + 10 },
					{ heroId = 2, level = 1, expiresAt = T0 - 1 },
					{ heroId = 2, level = 1, expiresAt = T0 + 1e6 },
					{ heroId = "2", level = 1, expiresAt = T0 + 10 },
				}
			do
				c.h:fireClient("ReplicatedStorage.Remotes.CheerPrompt", payload)
			end
			expect(hud(c).Cheer.Visible).toBe(false)
			expect(c.Input.requestCheer()).toBe(false)
			expect(#c.h:signalErrors()).toBe(0)
		end)
	end)

	describe("HUD › langue", function()
		it("les textes sont ré-appliqués sur LanguageChanged", function()
			local c = setup()
			local label = hud(c).Rail.Upgrades.Button.Label
			expect(label.Text).toBe("Upgrades")
			c.Prefs._onSettings({ lang = "fr" })
			c.h:settle(1)
			expect(label.Text).toBe(c.L.get("fr", "hud.rail.upgrades"))
			expect(hud(c).Cheer.Button.Title.Text).toBe(c.L.get("fr", "hud.cheer"))
		end)
	end)

	describe("HUD › revue (bogues corrigés)", function()
		local function prompt(c, heroId)
			c.h:fireClient(
				"ReplicatedStorage.Remotes.CheerPrompt",
				{ heroId = heroId, level = 2, expiresAt = c.Clock.now() + 10 }
			)
		end

		it("acclamer joue l'emote « cheer » sur son propre personnage (GDD §6.6)", function()
			local c = setup()
			snapshot(c)
			local played = {}
			c.h.localPlayer.Character.Humanoid.PlayEmote = function(_, name)
				table.insert(played, name)
				return true
			end
			c.h:addPlayer({ userId = 2, name = "Lea" })
			prompt(c, 2)
			hud(c).Cheer.Button.Activated:Fire()
			c.h:settle(2)
			expect(sent(c, "Cheer")[1][1]).toBe(2)
			expect(played[1]).toBe("cheer")
			-- personnage absent : l'acclamation part quand même, sans erreur
			c.Clock.advance(20)
			prompt(c, 2)
			c.h.localPlayer.Character = nil
			c.Input.requestCheer()
			c.h:settle(2)
			expect(#sent(c, "Cheer")).toBe(2)
			expect(#played).toBe(1)
			expect(#c.h:signalErrors()).toBe(0)
		end)

		it("le héros quitte le serveur : le bouton ACCLAMER disparaît, F ne fait plus rien", function()
			local c = setup()
			snapshot(c)
			local hero = c.h:addPlayer({ userId = 2, name = "Lea" })
			local other = c.h:addPlayer({ userId = 3, name = "Noah" })
			prompt(c, 2)
			expect(hud(c).Cheer.Visible).toBe(true)
			c.h:removePlayer(other)
			c.h:settle(2)
			expect(hud(c).Cheer.Visible).toBe(true) -- un autre joueur part : rien ne change
			c.h:removePlayer(hero)
			c.h:settle(2)
			expect(hud(c).Cheer.Visible).toBe(false)
			expect(c.Input.requestCheer()).toBe(false)
			expect(#sent(c, "Cheer")).toBe(0)
		end)

		it("petit écran (échelle 0,6) : Ping et Dash gardent une cible tactile ≥ 56 px réels", function()
			local c = setup({ touch = true })
			c.h.workspace.CurrentCamera.ViewportSize = Vector2.new(640, 360)
			local k = c.Root.scale()
			expect(k).toBe(0.6)
			c.HUD._layoutActions()
			local ping, dash = hud(c).Ping, hud(c).Dash
			expect(ping.Size.X.Offset * k >= 56).toBe(true)
			expect(ping.Size.Y.Offset * k >= 56).toBe(true)
			expect(dash.Size.X.Offset * k >= 56).toBe(true)
			-- le Ping reste collé à gauche du Dash
			expect(ping.Position).toEqual(dash.Position + UDim2.fromOffset(-dash.Size.X.Offset - 12, 0))
			-- écran de référence : tailles du GDD
			c.h.workspace.CurrentCamera.ViewportSize = Vector2.new(1280, 720)
			c.HUD._layoutActions()
			expect(ping.Size).toEqual(UDim2.fromOffset(72, 72))
			expect(dash.Size).toEqual(UDim2.fromOffset(112, 112))
		end)

		it("le suivi de quête glisse depuis la droite (GDD §3) au lieu d'un simple pop", function()
			local c = setup()
			local Juice = c.h:require(CLIENT .. "UI.Juice")
			local tweens = {}
			local original = Juice.tween
			Juice.tween = function(inst, duration, props, ...)
				table.insert(tweens, { inst = inst, props = props })
				return original(inst, duration, props, ...)
			end
			local holder = hud(c).QuestTracker
			local anchor = holder.Position
			c.HUD.reveal("questTracker", true)
			local slide = nil
			for _, t in tweens do
				if t.inst == holder and t.props.Position ~= nil then
					slide = t
				end
			end
			expect(slide ~= nil).toBe(true)
			expect(slide.props.Position).toEqual(anchor)
			expect(holder.Position).toEqual(anchor)
			expect(holder.HudScale.Scale).toBe(1)
			-- les autres éléments gardent le pop d'échelle
			c.HUD.reveal("stardust", true)
			local popped = false
			for _, t in tweens do
				if t.inst == hud(c).Stardust.HudScale and t.props.Scale == 1 then
					popped = true
				end
			end
			expect(popped).toBe(true)
		end)

		it(
			"Dash tactile : déclenché dès l'appui ; l'Activated du relâchement n'en relance pas un",
			function()
				local c = setup({ touch = true })
				snapshot(c)
				c.HUD.reveal("dash", false)
				local refused = 0
				c.Input.DashRefused:Connect(function()
					refused += 1
				end)
				local button = hud(c).Dash.Button
				button.InputBegan:Fire({ UserInputType = roblox.Enum.UserInputType.Touch })
				c.h:settle(1)
				expect(#sent(c, "Dash")).toBe(1) -- avant le relâchement
				frames(c, 3)
				button.Activated:Fire() -- relâchement du même geste
				c.h:settle(1)
				expect(#sent(c, "Dash")).toBe(1)
				expect(refused).toBe(0) -- pas de secousse « recharge » parasite
				-- manette (bouton sélectionné + A) : Activated seul, après la recharge
				c.Clock.advance(c.Formulas.dashCooldown(0) + 0.1)
				frames(c, 60)
				button.Activated:Fire()
				c.h:settle(1)
				expect(#sent(c, "Dash")).toBe(2)
				-- autres entrées (survol souris) : rien
				c.Clock.advance(c.Formulas.dashCooldown(0) + 0.1)
				button.InputBegan:Fire({ UserInputType = roblox.Enum.UserInputType.MouseMovement })
				c.h:settle(1)
				expect(#sent(c, "Dash")).toBe(2)
			end
		)

		it("Nuit de la Balise : la barre de serveur glisse en place (GDD §9.4)", function()
			local c = setup()
			c.HUD.reveal("eventPill", false)
			local Juice = c.h:require(CLIENT .. "UI.Juice")
			local slides = {}
			local original = Juice.tween
			Juice.tween = function(inst, duration, props, ...)
				if inst.Name == "BeaconBar" and props.Position then
					table.insert(slides, props.Position)
				end
				return original(inst, duration, props, ...)
			end
			local bar = hud(c).EventPill.BeaconBar
			local home = bar.Position
			c.events = {
				t = T0,
				beacon = {
					phase = "warn",
					warnAt = T0 - 5,
					startsAt = T0 + 10,
					endsAt = T0 + 190,
					points = 0,
					goal = 40,
				},
				wisps = {},
			}
			frames(c, 7)
			expect(bar.Visible).toBe(true)
			expect(#slides).toBe(1)
			expect(slides[1]).toEqual(home)
			expect(bar.Position).toEqual(home)
			-- déjà affichée : pas de nouvelle glissade à chaque mise à jour
			frames(c, 14)
			expect(#slides).toBe(1)
		end)

		it("file pleine en Mouvement réduit : contour rouge fixe, sans clignotement", function()
			local c = setup()
			snapshot(c)
			c.Prefs._onSettings({ reducedMotion = true })
			local stroke = hud(c).LineCounter.Pill:FindFirstChildOfClass("UIStroke")
			local danger = c.h:require(CLIENT .. "UI.Theme").Colors.Danger
			c.h:fireClient(
				"ReplicatedStorage.Remotes.Feedback",
				{ key = "feedback.lineFull", vars = {}, tone = "warning" }
			)
			for _ = 1, 5 do
				frames(c, 1, 0.05) -- 0,05 → 0,25 s
				expect(stroke.Color).toBe(danger)
			end
			frames(c, 4, 0.05)
			expect(stroke.Color ~= danger).toBe(true)
		end)

		it(
			"Q5 : fin de la pulsation du Dash, la main revient sur Améliorer (toujours en attention)",
			function()
				local c = setup()
				c.HUD.reveal("rail.Upgrades", false)
				c.HUD.reveal("dash", false)
				c.HUD.attention("rail.Upgrades", true)
				c.HUD.attention("dash", true)
				local st = c.HUD._state()
				expect(st.handTarget).toBe(st.elements.dash)
				c.HUD.attention("dash", false)
				st = c.HUD._state()
				expect(st.handTarget).toBe(st.elements["rail.Upgrades"])
				c.HUD.attention("rail.Upgrades", false)
				expect(c.HUD._state().handTarget).toBeNil()
			end
		)

		it("reflet des boutons ronds (Dash, Ping) : calque arrondi comme le bouton", function()
			local c = setup()
			local round = roblox.UDim.new(1, 0)
			expect(hud(c).Dash.Button.Shine.UICorner.CornerRadius).toEqual(round)
			-- boutons carrés du rail : arrondi du bouton
			local rail = hud(c).Rail.Upgrades.Button
			expect(rail.Shine.UICorner.CornerRadius).toEqual(rail.UICorner.CornerRadius)
		end)
	end)
end
