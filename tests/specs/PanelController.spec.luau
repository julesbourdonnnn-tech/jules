--!nocheck
-- PanelController (paquet client-panels) : navigation des panneaux (un seul ouvert, retour,
-- bascule, onglets LB/RB, construction paresseuse), fenêtre §10.3 et animations §9.2, actions
-- manette liées seulement quand un panneau est ouvert, pastilles « ! » (BadgeChanged),
-- propriétaire des remotes CrewInvitePrompt (charges malveillantes) et de l'écran de retour
-- (Celebrate "offline"), contour rose hors du port sûr (§13.2), cycle de vie (réapparition).
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000

	local function profile(over)
		local p = {
			version = 1,
			glow = 0,
			glowCarry = 0,
			lastSettle = T0,
			lastOnline = T0,
			idleRate = 0,
			stardust = 0,
			supernovas = 0,
			upgrades = { conga = 0, stride = 0, lure = 0, perches = 0, guard = 0 },
			boosts = { personalUntil = 0 },
			caps = { day = 0, snipDust = 0, wispDust = 0, cheers = 0, duo = false },
			nebbies = {},
			nextUid = 1,
			perchIncome = 0,
			atlas = { 0, 0, 0, 0, 0, 0, 0 },
			badges = { 0, 0, 0, 0 },
			atlasRewards = 0,
			onboarding = { step = 8, p = 0 },
			daily = { day = math.floor(T0 / 86400), step = 2 },
			quests = { day = 0, list = {}, rerolls = 0, starClaimed = false },
			weekly = { week = 0, banked = 0, claimed = false },
			rookie = { sessions = 3, playSeconds = 4000, done = true },
			settings = {
				zen = false,
				reducedMotion = false,
				lowGraphics = false,
				music = true,
				sfx = true,
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

	local function setup(over, opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", touch = opts.touch })
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
			ScreenFX = h:require(CLIENT .. "UI.ScreenFX"),
			PC = h:require(CLIENT .. "Controllers.PanelController"),
			WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
			Balance = h:require("ReplicatedStorage.Shared.Config.Balance"),
		}
		c.errors0 = #h:signalErrors()
		c.Root.Init()
		c.State.Init()
		c.Prefs.Init()
		c.WSC.Init()
		c.State.Start()
		c.Prefs.Start()
		c.WSC.Start()
		c.PC.Init()
		c.PC.Start()
		if over ~= false then
			h:fireClient(REMOTES .. "DataSnapshot", profile(over))
		end
		h:settle(1)
		return c
	end

	local function frames(c, n, dt)
		for _ = 1, n do
			c.Clock.advance(dt or 0.05)
			c.h:step(dt or 0.05, 1)
		end
	end

	local function sent(c, name)
		local out = {}
		for _, e in c.h.log.serverEvents do
			if e.remote == name then
				table.insert(out, e.args)
			end
		end
		return out
	end

	local function signalErrors(c)
		return #c.h:signalErrors() - c.errors0
	end

	local function window(c)
		return c.h.localPlayer.PlayerGui.Panels.Safe.Window
	end

	local function placeAt(c, player, pos)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		root.CFrame = CFrame.new(pos)
	end

	describe("PanelController › navigation", function()
		it("ouvre un seul panneau à la fois et émet Opened / Closed", function()
			local c = setup()
			local opened, closed = {}, {}
			c.PC.Opened:Connect(function(name)
				table.insert(opened, name)
			end)
			c.PC.Closed:Connect(function(name)
				table.insert(closed, name)
			end)
			expect(c.PC.current()).toBeNil()
			c.PC.open("Upgrades")
			expect(c.PC.current()).toBe("Upgrades")
			c.PC.open("Shop")
			expect(c.PC.current()).toBe("Shop")
			expect(c.PC.page("Upgrades").Visible).toBe(false)
			expect(c.PC.page("Shop").Visible).toBe(true)
			c.PC.close()
			expect(c.PC.current()).toBeNil()
			c.PC.close() -- sans effet
			expect(opened).toEqual({ "Upgrades", "Shop" })
			expect(closed).toEqual({ "Upgrades", "Shop" })
			expect(#c.h:warnings()).toBe(0)
		end)

		it("toggle ouvre puis ferme ; back revient au parent puis ferme", function()
			local c = setup()
			c.PC.toggle("Goals")
			expect(c.PC.current()).toBe("Goals")
			c.PC.toggle("Goals")
			expect(c.PC.current()).toBeNil()
			c.PC.open("Supernova")
			c.PC.back()
			expect(c.PC.current()).toBe("Upgrades")
			c.PC.back()
			expect(c.PC.current()).toBeNil()
			c.PC.back() -- rien d'ouvert
			expect(c.PC.current()).toBeNil()
		end)

		it("ignore un nom de panneau inconnu ou malveillant sans erreur", function()
			local c = setup()
			for _, bad in { "Nope", "", 42, {}, 0 / 0 } do
				c.PC.open(bad)
				c.PC.toggle(bad)
				expect(c.PC.hasAction(bad)).toBe(false)
			end
			expect(c.PC.current()).toBeNil()
			expect(signalErrors(c)).toBe(0)
		end)

		it("construit chaque panneau paresseusement, une seule fois", function()
			local c = setup()
			expect(c.PC.page("Collection")).toBeNil()
			c.PC.open("Collection")
			local page = c.PC.page("Collection")
			expect(page ~= nil).toBe(true)
			c.PC.close()
			c.PC.open("Collection")
			expect(c.PC.page("Collection")).toBe(page)
			local count = 0
			for _, child in window(c):GetChildren() do
				if child.Name == "Page_Collection" then
					count += 1
				end
			end
			expect(count).toBe(1)
		end)

		it("ouvre chacun des 8 panneaux sans erreur ni avertissement", function()
			local c = setup()
			for _, name in c.PC.NAMES do
				c.PC.open(name)
				expect(c.PC.current()).toBe(name)
				frames(c, 3)
			end
			c.PC.close()
			frames(c, 3)
			expect(signalErrors(c)).toBe(0)
			expect(#c.h:warnings()).toBe(0)
		end)
	end)

	describe("PanelController › fenêtre et animations (§10.3, §9.2)", function()
		it(
			"fenêtre 0,72 × 0,86 bornée 480 × 320 – 900 × 600, onglets 56 px, Fermer 64 × 64",
			function()
				local c = setup()
				c.PC.open("Collection")
				local w = window(c)
				expect(w.ClassName).toBe("CanvasGroup")
				expect(w.Size).toEqual(c.g.UDim2.fromScale(0.72, 0.86))
				local constraint = w:FindFirstChildOfClass("UISizeConstraint")
				expect(constraint.MinSize).toEqual(c.g.Vector2.new(480, 320))
				expect(constraint.MaxSize).toEqual(c.g.Vector2.new(900, 600))
				local page = c.PC.page("Collection")
				expect(page.Tabs.Size.Y.Offset).toBe(56)
				expect(page.Header.Close.Size).toEqual(c.g.UDim2.fromOffset(64, 64))
				expect(w.Visible).toBe(true)
				expect(w.GroupTransparency).toBe(0)
				expect(w.SelectionGroup).toBe(true)
			end
		)

		it("écran de retour en fenêtre réduite, puis taille normale", function()
			local c = setup()
			c.PC.open("ReturnScreen", { data = { glow = 10, seconds = 60 } })
			expect(window(c).Size).toEqual(c.g.UDim2.fromScale(0.5, 0.62))
			c.PC.open("Shop")
			expect(window(c).Size).toEqual(c.g.UDim2.fromScale(0.72, 0.86))
		end)

		it(
			"flou 0 → 8 à l'ouverture, aucun avec Graphismes légers ; fermeture cachée après 0,12 s",
			function()
				local c = setup()
				c.PC.open("Upgrades")
				local blur = c.h.game.Lighting.PanelBlur
				expect(blur.Size).toBe(8)
				c.PC.close()
				expect(blur.Size).toBe(0)
				task.wait(0.2)
				expect(window(c).Visible).toBe(false)
				c.Prefs._onSettings({ lowGraphics = true, lang = "en" })
				c.PC.open("Upgrades")
				expect(blur.Size).toBe(0)
			end
		)

		it("rouvrir pendant le fondu de fermeture garde la fenêtre visible", function()
			local c = setup()
			c.PC.open("Upgrades")
			c.PC.close()
			c.PC.open("Goals")
			task.wait(0.2)
			expect(window(c).Visible).toBe(true)
			expect(c.PC.page("Goals").Visible).toBe(true)
			expect(c.PC.page("Upgrades").Visible).toBe(false)
		end)

		it("Mouvement réduit : ouverture en fondu, échelle fixe", function()
			local c = setup({ settings = { reducedMotion = true, lang = "en" } })
			c.PC.open("Shop")
			local scale = window(c):FindFirstChild("JuiceScale")
			expect(scale.Scale).toBe(1)
			expect(window(c).GroupTransparency).toBe(0)
		end)

		it("titres et onglets traduits, ré-appliqués au changement de langue", function()
			local c = setup()
			c.PC.open("Collection")
			local page = c.PC.page("Collection")
			expect(page.Header.Title.Text).toBe("Collection")
			expect(page.Tabs.Tab_stash.Label.Text).toBe("Stash")
			c.Prefs._onSettings({ lang = "fr" })
			c.h:settle(1)
			expect(page.Tabs.Tab_stash.Label.Text).toBe("Réserve")
		end)
	end)

	describe("PanelController › onglets et manette (§10.4)", function()
		it("args.tab choisit l'onglet ; nextTab boucle dans les deux sens", function()
			local c = setup()
			c.PC.open("Collection", { tab = "atlas" })
			expect(c.PC.currentTab("Collection")).toBe("atlas")
			c.PC.nextTab(1)
			expect(c.PC.currentTab("Collection")).toBe("guide")
			c.PC.nextTab(1)
			expect(c.PC.currentTab("Collection")).toBe("perches")
			c.PC.nextTab(-1)
			expect(c.PC.currentTab("Collection")).toBe("guide")
			-- l'onglet est mémorisé d'une ouverture à l'autre
			c.PC.close()
			c.PC.open("Collection")
			expect(c.PC.currentTab("Collection")).toBe("guide")
			-- onglet inconnu : on garde le courant
			c.PC.open("Collection", { tab = "hack" })
			expect(c.PC.currentTab("Collection")).toBe("guide")
		end)

		it("nextTab ignore les directions invalides et les panneaux sans onglets", function()
			local c = setup()
			c.PC.nextTab(1) -- rien d'ouvert
			c.PC.open("Shop")
			local before = c.PC.currentTab("Shop")
			for _, bad in { 0, 0 / 0, "x", {} } do
				c.PC.nextTab(bad)
			end
			expect(c.PC.currentTab("Shop")).toBe(before)
			c.PC.open("Settings")
			c.PC.nextTab(1)
			expect(c.PC.current()).toBe("Settings")
			expect(signalErrors(c)).toBe(0)
		end)

		it("l'onglet Accueil n'existe que tant que la chaîne n'est pas finie", function()
			local c = setup({ onboarding = { step = 3, p = 1 } })
			c.PC.open("Goals", { tab = "welcome" })
			expect(c.PC.currentTab("Goals")).toBe("welcome")
			c.h:fireClient(REMOTES .. "DataPatch", { onboarding = { step = 8, p = 0 } }, {})
			frames(c, 2)
			expect(c.PC.page("Goals").Tabs.Tab_welcome.Visible).toBe(false)
			expect(c.PC.currentTab("Goals")).toBe("today")
			for _ = 1, 5 do
				c.PC.nextTab(1)
				expect(c.PC.currentTab("Goals") ~= "welcome").toBe(true)
			end
		end)

		it(
			"B / Échap et LB / RB ne sont liés que pendant qu'un panneau est ouvert, et absorbés",
			function()
				local c = setup()
				expect(c.h.actions.PanelBack).toBeNil()
				c.PC.open("Collection")
				expect(c.h.actions.PanelBack ~= nil).toBe(true)
				local result = c.h.actions.PanelTabNext("PanelTabNext", Enum.UserInputState.Begin, nil)
				expect(result).toBe(Enum.ContextActionResult.Sink)
				expect(c.PC.currentTab("Collection")).toBe("stash")
				c.h.actions.PanelTabPrev("PanelTabPrev", Enum.UserInputState.Begin, nil)
				expect(c.PC.currentTab("Collection")).toBe("perches")
				c.h.actions.PanelTabPrev("PanelTabPrev", Enum.UserInputState.End, nil) -- relâchement : rien
				expect(c.PC.currentTab("Collection")).toBe("perches")
				c.h.actions.PanelBack("PanelBack", Enum.UserInputState.Begin, nil)
				expect(c.PC.current()).toBeNil()
				expect(c.h.actions.PanelBack).toBeNil()
				expect(c.h.actions.PanelTabNext).toBeNil()
			end
		)

		it("B dans l'aperçu de Supernova revient à Améliorer", function()
			local c = setup()
			c.PC.open("Supernova")
			c.h.actions.PanelBack("PanelBack", Enum.UserInputState.Begin, nil)
			expect(c.PC.current()).toBe("Upgrades")
		end)

		it("sélectionne le premier bouton à la manette seulement", function()
			local c = setup()
			local gs = c.h.game.GuiService
			c.PC.open("Shop")
			expect(gs.SelectedObject).toBeNil()
			c.PC.close()
			local cm = require("../harness/MockInstance").classMethods.UserInputService
			local previous = cm.GetLastInputType
			cm.GetLastInputType = function()
				return Enum.UserInputType.Gamepad1
			end
			c.PC.open("Shop")
			expect(gs.SelectedObject ~= nil).toBe(true)
			expect(gs.SelectedObject:IsDescendantOf(window(c))).toBe(true)
			c.PC.close()
			expect(gs.SelectedObject).toBeNil()
			cm.GetLastInputType = previous
		end)
	end)

	describe("PanelController › pastilles « ! »", function()
		it("BadgeChanged suit hasAction (Glow prédit, calendrier)", function()
			local c = setup({ glow = 10 })
			local seen = {}
			c.PC.BadgeChanged:Connect(function(name, value)
				seen[name] = value
			end)
			frames(c, 2)
			expect(c.PC.hasAction("Upgrades")).toBe(false)
			c.h:fireClient(REMOTES .. "DataPatch", { glow = 60 }, {})
			frames(c, 2)
			expect(c.PC.hasAction("Upgrades")).toBe(true)
			expect(seen.Upgrades).toBe(true)
			-- revenu passif : le Glow prédit rend l'achat possible sans patch
			c.h:fireClient(REMOTES .. "DataPatch", { glow = 0, idleRate = 10, lastSettle = T0 }, {})
			frames(c, 2)
			expect(seen.Upgrades).toBe(false)
			c.Clock.advance(6)
			frames(c, 25)
			expect(seen.Upgrades).toBe(true)
			-- minuit UTC : le calendrier devient réclamable
			expect(c.PC.hasAction("Goals")).toBe(false)
			c.Clock.advance(86400)
			frames(c, 25)
			expect(seen.Goals).toBe(true)
		end)

		it("aucune pastille avant l'instantané, ni sur la Boutique", function()
			local c = setup(false)
			local fired = 0
			c.PC.BadgeChanged:Connect(function()
				fired += 1
			end)
			frames(c, 30)
			expect(fired).toBe(0)
			c.h:fireClient(REMOTES .. "DataSnapshot", profile({ glow = 10 ^ 9 }))
			frames(c, 2)
			expect(c.PC.hasAction("Shop")).toBe(false)
			expect(c.PC.hasAction("Upgrades")).toBe(true)
		end)
	end)

	describe("PanelController › remote CrewInvitePrompt", function()
		it("rejette les charges malveillantes sans erreur", function()
			local c = setup()
			local Crew = c.h:require(CLIENT .. "UI.Panels.Crew")
			local bad = {
				nil,
				"x",
				42,
				{},
				{ inviterId = "1", expiresAt = T0 + 20 },
				{ inviterId = 0 / 0, expiresAt = T0 + 20 },
				{ inviterId = math.huge, expiresAt = T0 + 20 },
				{ inviterId = -5, expiresAt = T0 + 20 },
				{ inviterId = 2.5, expiresAt = T0 + 20 },
				{ inviterId = 2, expiresAt = 0 / 0 },
				{ inviterId = 2, expiresAt = -math.huge },
				{ inviterId = 2, expiresAt = T0 - 1 }, -- expirée
				{ inviterId = 999, expiresAt = T0 + 20 }, -- joueur absent
			}
			c.h:addPlayer({ userId = 2, name = "Mira" })
			for _, payload in bad do
				c.h:fireClient(REMOTES .. "CrewInvitePrompt", payload)
			end
			expect(Crew._shown()).toBeNil()
			expect(#Crew._pending()).toBe(0)
			expect(signalErrors(c)).toBe(0)
		end)

		it("une invitation valide affiche la carte ; « Refuser les invitations » la masque", function()
			local c = setup()
			local Crew = c.h:require(CLIENT .. "UI.Panels.Crew")
			c.h:addPlayer({ userId = 2, name = "Mira" })
			c.h:fireClient(REMOTES .. "CrewInvitePrompt", { inviterId = 2, expiresAt = T0 + 20 })
			expect(Crew._shown().inviterId).toBe(2)
			expect(Crew._card().Visible).toBe(true)
			expect(Crew._card().Text.Text).toBe("Mira invites you!")
			-- la carte ne bloque pas : aucun panneau n'est ouvert
			expect(c.PC.current()).toBeNil()
			local h2 = setup({ settings = { refuseInvites = true, lang = "en" } })
			local Crew2 = h2.h:require(CLIENT .. "UI.Panels.Crew")
			h2.h:addPlayer({ userId = 3, name = "Noah" })
			h2.h:fireClient(REMOTES .. "CrewInvitePrompt", { inviterId = 3, expiresAt = T0 + 20 })
			expect(Crew2._shown()).toBeNil()
		end)
	end)

	describe("PanelController › écran de retour", function()
		it("Celebrate offline ouvre l'écran de retour avec les données", function()
			local c = setup()
			c.ScreenFX.Celebrated:Fire({ kind = "offline", data = { glow = 1240000, seconds = 18720 } })
			c.h:settle(1)
			expect(c.PC.current()).toBe("ReturnScreen")
			local RS = c.h:require(CLIENT .. "UI.Panels.ReturnScreen")
			expect(RS._data().glow).toBe(1240000)
		end)

		it("ignore les autres célébrations et les données malformées", function()
			local c = setup()
			for _, payload in
				{
					nil,
					1,
					{},
					{ kind = "offline" },
					{ kind = "offline", data = "x" },
					{ kind = "upgrade", data = {} },
				}
			do
				c.ScreenFX.Celebrated:Fire(payload)
			end
			c.h:settle(1)
			expect(c.PC.current()).toBeNil()
			expect(signalErrors(c)).toBe(0)
		end)
	end)

	describe("PanelController › contour rose hors du port sûr (§13.2)", function()
		local function arm(c)
			local me = c.h.localPlayer
			me:SetAttribute("Slot", 1)
			c.WSC.lineLength = function()
				return 5
			end
			local gate = c.WorldLayout.gateCFrame(1).Position
			-- loin du port sûr, vers le centre de l'île
			local away = gate * 0.5
			placeAt(c, me, Vector3.new(away.X, 3, away.Z))
			local other = c.h:addPlayer({ userId = 7, name = "Rival" })
			return away, other
		end

		it("s'allume quand un non-équipier approche de la file, panneau ouvert", function()
			local c = setup()
			local away, other = arm(c)
			placeAt(c, other, Vector3.new(away.X + 6, 3, away.Z))
			expect(c.PC._tailThreatened()).toBe(true)
			c.PC.open("Collection")
			frames(c, 6)
			local warnFrame = c.h.localPlayer.PlayerGui.Panels.TailWarning
			expect(warnFrame.Visible).toBe(true)
			c.PC.close()
			expect(warnFrame.Visible).toBe(false)
		end)

		it("reste éteint : loin, équipier, Zen, port sûr, file vide, sans personnage", function()
			local c = setup()
			local away, other = arm(c)
			placeAt(c, other, Vector3.new(away.X + 40, 3, away.Z))
			expect(c.PC._tailThreatened()).toBe(false)
			placeAt(c, other, Vector3.new(away.X + 6, 3, away.Z))
			c.WSC.isCrewmate = function(userId)
				return userId == 7
			end
			expect(c.PC._tailThreatened()).toBe(false)
			c.WSC.isCrewmate = function()
				return false
			end
			c.h.localPlayer:SetAttribute("Zen", true)
			expect(c.PC._tailThreatened()).toBe(false)
			c.h.localPlayer:SetAttribute("Zen", false)
			local gate = c.WorldLayout.gateCFrame(1).Position
			placeAt(c, c.h.localPlayer, Vector3.new(gate.X, 3, gate.Z))
			placeAt(c, other, Vector3.new(gate.X + 4, 3, gate.Z))
			expect(c.PC._tailThreatened()).toBe(false)
			placeAt(c, c.h.localPlayer, Vector3.new(away.X, 3, away.Z))
			placeAt(c, other, Vector3.new(away.X + 6, 3, away.Z))
			c.WSC.lineLength = function()
				return 0
			end
			expect(c.PC._tailThreatened()).toBe(false)
			c.h.localPlayer.Character:Destroy()
			c.h.localPlayer.Character = nil
			expect(c.PC._tailThreatened()).toBe(false)
		end)
	end)

	-- Revue du paquet : chaque test reproduit un défaut trouvé, corrigé ensuite
	describe("PanelController › revue (défauts corrigés)", function()
		it("contour rose : un non-équipier en Mode Zen ne peut pas couper → pas d'alerte", function()
			local c = setup()
			local me = c.h.localPlayer
			me:SetAttribute("Slot", 1)
			c.WSC.lineLength = function()
				return 5
			end
			local away = c.WorldLayout.gateCFrame(1).Position * 0.5
			placeAt(c, me, Vector3.new(away.X, 3, away.Z))
			local other = c.h:addPlayer({ userId = 7, name = "Calm" })
			placeAt(c, other, Vector3.new(away.X + 6, 3, away.Z))
			expect(c.PC._tailThreatened()).toBe(true)
			other:SetAttribute("Zen", true)
			expect(c.PC._tailThreatened()).toBe(false)
		end)

		it(
			"Celebrate « offline » reçu entre Init et Start : l'écran de retour s'ouvre quand même",
			function()
				local h = Harness.new({ mode = "client" })
				h:createRemotes()
				local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
				Clock.freeze(T0)
				local Root = h:require(CLIENT .. "UI.Root")
				local State = h:require(CLIENT .. "Controllers.StateController")
				local Prefs = h:require(CLIENT .. "Util.Prefs")
				local ScreenFX = h:require(CLIENT .. "UI.ScreenFX")
				local PC = h:require(CLIENT .. "Controllers.PanelController")
				Root.Init()
				State.Init()
				Prefs.Init()
				PC.Init()
				-- le signal de ScreenFX part avant PanelController.Start (ordre de démarrage §13.1)
				ScreenFX.Celebrated:Fire({ kind = "offline", data = { glow = 5000, seconds = 3600 } })
				h:settle(1)
				PC.Start()
				h:settle(1)
				expect(PC.current()).toBe("ReturnScreen")
			end
		)

		it("Graphismes légers activé pendant qu'un panneau est ouvert : le flou s'éteint", function()
			local c = setup()
			c.PC.open("Goals")
			frames(c, 2)
			local blur = c.h.game.Lighting.PanelBlur
			expect(blur.Size).toBe(8)
			c.Prefs._onSettings({ lowGraphics = true, lang = "en" })
			c.h:settle(1)
			expect(blur.Size).toBe(0)
			c.Prefs._onSettings({ lowGraphics = false, lang = "en" })
			c.h:settle(1)
			expect(blur.Size).toBe(8)
			c.PC.close()
			c.Prefs._onSettings({ lowGraphics = true, lang = "en" })
			c.h:settle(1)
			expect(blur.Size).toBe(0)
		end)
	end)

	describe("PanelController › cycle de vie", function()
		it("la réapparition ne ferme ni ne détruit le panneau ouvert", function()
			local c = setup()
			c.PC.open("Goals")
			c.h:respawn(c.h.localPlayer)
			frames(c, 5)
			expect(c.PC.current()).toBe("Goals")
			expect(c.h.localPlayer.PlayerGui.Panels.ResetOnSpawn).toBe(false)
			expect(c.PC.page("Goals").Parent ~= nil).toBe(true)
			expect(signalErrors(c)).toBe(0)
		end)

		it("démarrage complet du client (Main) : les panneaux s'ouvrent sans erreur", function()
			local h = Harness.new({ mode = "client", touch = true })
			h:createRemotes()
			h:boot()
			h:fireClient(REMOTES .. "DataSnapshot", profile({ glow = 500 }))
			local PC = h:require(CLIENT .. "Controllers.PanelController")
			for _, name in PC.NAMES do
				PC.open(name)
				h:step(1 / 30, 2)
			end
			PC.close()
			h:step(1 / 30, 5)
			expect(#h:signalErrors()).toBe(0)
		end)
	end)
end
