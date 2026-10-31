--!nocheck
-- Correctifs r4 « client-0 » (PanelController) :
--   * sélection manette effacée pendant qu'un panneau est ouvert (pavé tactile / Créer de la
--     DualSense, menu du système…) : rendue tout de suite (dernier objet de la fenêtre, sinon
--     sélection par défaut) ; vide seulement tant qu'une fenêtre Roblox tient la manette (achat :
--     effacée juste après ✕ dans la fenêtre, PanelController.holdSelection, menu du système) ; la
--     croix sans sélection n'ouvre jamais la roue de pings, la minicarte ni ACCLAMER derrière la
--     fenêtre
--   * contour rose « queue menacée » (panneau ouvert) aligné sur les règles du serveur et du contour
--     de CongaRenderer : trêve de la Balise en phase « success », immunité de la victime
--     (ImmuneUntil), seule la queue coupable (au-delà des Guard Links, GDD §4.7, §6.4)
local roblox = require("@lune/roblox")
local Gamepad = require("../harness/Gamepad")
local Layout = require("../harness/Layout")
local ApiAudit = require("../harness/ApiAudit")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000
	local TODAY = math.floor(T0 / 86400)
	local K = Enum.KeyCode
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

	-- =============================================================================================
	-- Sélection manette toujours rendue (client console complet)
	-- =============================================================================================

	local function boot(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = true })
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
		h:fireClient(REMOTES .. "DataSnapshot", profile())
		h:step(1 / 60, 30)
		h:settle(3)
		local c = {
			h = h,
			Clock = Clock,
			PC = h:require(CLIENT .. "Controllers.PanelController"),
			Input = h:require(CLIENT .. "Controllers.InputController"),
			minimap = 0,
		}
		c.Input.MinimapToggled:Connect(function()
			c.minimap += 1
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

	local function openFresh(c, name, tab)
		c.PC.close()
		frames(c, 8)
		c.h.game.GuiService.SelectedObject = nil
		c.PC.open(name, if tab then { tab = tab } else nil)
		frames(c, 8)
		Layout.apply(c.h)
	end

	local function inside(c)
		local s = selected(c)
		return s ~= nil and s:IsDescendantOf(window(c))
	end

	describe("Fix r4 client-0 › sélection effacée panneau ouvert (pavé tactile, menu)", function()
		it(
			"effacée sans fenêtre Roblox : rendue à l'image suivante, la croix ↑ n'ouvre pas la roue",
			function()
				local c = boot()
				openFresh(c, "Upgrades")
				local first = selected(c)
				expect(inside(c)).toBe(true)
				-- pavé tactile de la DualSense (ButtonSelect bascule la sélection de Roblox)
				Gamepad.tap(c.h, K.ButtonSelect)
				c.h.game.GuiService.SelectedObject = nil
				frames(c, 2)
				expect(selected(c)).toBe(first)
				-- effacée de nouveau, croix ↑ dans la même image : absorbée, sélection rendue, pas de roue
				c.h.game.GuiService.SelectedObject = nil
				expect(Gamepad.tap(c.h, K.DPadUp) ~= "CC_PingWheel").toBe(true)
				expect(c.Input.isPingWheelOpen()).toBe(false)
				expect(inside(c)).toBe(true)
				-- croix ↓ sans sélection : la minicarte derrière la fenêtre ne bascule pas
				c.h.game.GuiService.SelectedObject = nil
				Gamepad.tap(c.h, K.DPadDown)
				expect(c.minimap).toBe(0)
				expect(inside(c)).toBe(true)
				-- croix → sans sélection : pas d'ACCLAMER, sélection rendue
				c.h.game.GuiService.SelectedObject = nil
				Gamepad.tap(c.h, K.DPadRight)
				expect(inside(c)).toBe(true)
				-- 10 images plus tard : toujours une sélection valide dans la fenêtre
				c.h.game.GuiService.SelectedObject = nil
				frames(c, 10)
				expect(inside(c)).toBe(true)
				expect(c.PC.current()).toBe("Upgrades")
				-- panneau fermé : la croix ↑ ouvre bien la roue (rien n'est lié en jeu)
				c.PC.close()
				frames(c, 8)
				c.h.game.GuiService.SelectedObject = nil
				expect(Gamepad.tap(c.h, K.DPadUp)).toBe("CC_PingWheel")
				expect(c.Input.isPingWheelOpen()).toBe(true)
				finish(c)
			end
		)

		it("objet effacé ET masqué : sélection par défaut du panneau", function()
			local c = boot()
			openFresh(c, "Shop", "passes")
			local default = selected(c)
			expect(default.Name).toBe("Buy")
			c.PC.open("Shop", { tab = "boosts" })
			frames(c, 4)
			local now = selected(c)
			expect(inside(c)).toBe(true)
			-- l'objet sélectionné disparaît pendant que la sélection est vide
			c.h.game.GuiService.SelectedObject = nil
			now.Visible = false
			frames(c, 2)
			expect(inside(c)).toBe(true)
			expect(selected(c) ~= now).toBe(true)
			finish(c)
		end)

		it(
			"holdSelection(true) garde la sélection vide ; false, ou la croix arrivée au jeu, la rend",
			function()
				local c = boot()
				openFresh(c, "Upgrades")
				local first = selected(c)
				c.PC.holdSelection(true)
				c.h.game.GuiService.SelectedObject = nil
				frames(c, 6)
				expect(selected(c)).toBeNil()
				c.PC.holdSelection(false)
				frames(c, 2)
				expect(selected(c)).toBe(first)
				-- garde oubliée : une croix qui arrive au jeu prouve qu'aucune fenêtre Roblox ne tient la
				-- manette → sélection rendue, roue fermée
				c.PC.holdSelection(true)
				c.h.game.GuiService.SelectedObject = nil
				frames(c, 2)
				expect(selected(c)).toBeNil()
				Gamepad.tap(c.h, K.DPadUp)
				expect(c.Input.isPingWheelOpen()).toBe(false)
				expect(selected(c)).toBe(first)
				frames(c, 2)
				expect(selected(c)).toBe(first)
				-- fermeture : la garde tombe avec le panneau
				c.PC.holdSelection(true)
				c.PC.close()
				frames(c, 8)
				openFresh(c, "Upgrades")
				c.h.game.GuiService.SelectedObject = nil
				frames(c, 2)
				expect(inside(c)).toBe(true)
				finish(c)
			end
		)

		it("menu du système ouvert : sélection laissée vide, rendue à sa fermeture", function()
			local c = boot({ audit = false })
			openFresh(c, "Upgrades")
			local first = selected(c)
			c.h.game.GuiService.MenuIsOpen = true
			c.h.game.GuiService.SelectedObject = nil
			frames(c, 6)
			expect(selected(c)).toBeNil()
			c.h.game.GuiService.MenuIsOpen = false
			frames(c, 2)
			expect(selected(c)).toBe(first)
			finish(c, false)
		end)

		it(
			"fenêtre d'achat Roblox (effacée juste après ✕ sur Acheter) : vide jusqu'à la fin de l'achat",
			function()
				local c = boot()
				openFresh(c, "Shop", "passes")
				local buy = c.PC.page("Shop").Body.Tab_passes.VIPStar.Buy
				c.h.game.GuiService.SelectedObject = buy
				frames(c, 2)
				Gamepad.tap(c.h, K.ButtonA)
				expect(#c.h.log.prompts).toBe(1)
				c.h.game.GuiService.SelectedObject = nil
				frames(c, 30)
				expect(selected(c)).toBeNil()
				c.h.game.MarketplaceService.PromptGamePassPurchaseFinished:Fire(
					c.h.localPlayer,
					PASS_ID,
					false
				)
				frames(c, 2)
				expect(selected(c)).toBe(buy)
				-- un ✕ ancien (> 3 s) suivi d'un effacement n'est pas une fenêtre d'achat
				Gamepad.tap(c.h, K.ButtonA)
				c.h.game.MarketplaceService.PromptGamePassPurchaseFinished:Fire(
					c.h.localPlayer,
					PASS_ID,
					false
				)
				frames(c, 2)
				frames(c, 120)
				c.h.game.GuiService.SelectedObject = nil
				frames(c, 2)
				expect(selected(c)).toBe(buy)
				finish(c)
			end
		)
	end)

	-- =============================================================================================
	-- Contour rose « queue menacée » : mêmes règles que le serveur
	-- =============================================================================================

	local function setup(over)
		local h = Harness.new({ mode = "client" })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = {
			h = h,
			Clock = Clock,
			Root = h:require(CLIENT .. "UI.Root"),
			State = h:require(CLIENT .. "Controllers.StateController"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			WSC = h:require(CLIENT .. "Controllers.WorldStateController"),
			CR = h:require(CLIENT .. "Controllers.CongaRenderer"),
			PC = h:require(CLIENT .. "Controllers.PanelController"),
			WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
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

	local function placeAt(player, pos)
		player.Character.HumanoidRootPart.CFrame = CFrame.new(pos)
	end

	-- File locale de `n` Nebbies hors du port sûr, un rival non équipier à 6 studs de la tête
	local function arm(c, n)
		local me = c.h.localPlayer
		me:SetAttribute("Slot", 1)
		c.WSC.lineLength = function()
			return n
		end
		local away = c.WorldLayout.gateCFrame(1).Position * 0.5
		local head = Vector3.new(away.X, 3, away.Z)
		placeAt(me, head)
		local other = c.h:addPlayer({ userId = 7, name = "Rival" })
		placeAt(other, Vector3.new(head.X + 6, 3, head.Z))
		return head, other
	end

	describe("Fix r4 client-0 › contour rose : trêve, immunité, Guard Links", function()
		it("trêve de la Balise en phase « success » (rush de Frénésie) : pas d'alerte", function()
			local c = setup()
			arm(c, 6)
			expect(c.PC._tailThreatened()).toBe(true)
			local beacon = { phase = "success", startsAt = T0 - 30, endsAt = T0 + 60, points = 0, goal = 1 }
			c.WSC.events = function()
				return { beacon = beacon }
			end
			expect(c.PC._tailThreatened()).toBe(false)
			beacon.phase = "active"
			expect(c.PC._tailThreatened()).toBe(false)
			-- trêve finie (endsAt passé) ou pas encore commencée : l'alerte revient
			beacon.phase = "success"
			c.Clock.advance(61)
			expect(c.PC._tailThreatened()).toBe(true)
			beacon.phase, beacon.startsAt, beacon.endsAt = "active", T0 + 200, T0 + 400
			expect(c.PC._tailThreatened()).toBe(true)
			beacon.phase = "warning"
			beacon.startsAt, beacon.endsAt = T0, T0 + 400
			expect(c.PC._tailThreatened()).toBe(true)
			-- coupes désactivées (snipsDisabled) : jamais d'alerte
			c.WSC.events = function()
				return { snipsDisabled = true }
			end
			expect(c.PC._tailThreatened()).toBe(false)
		end)

		it("victime immunisée (ImmuneUntil dans le futur) : pas d'alerte", function()
			local c = setup()
			arm(c, 6)
			c.h.localPlayer:SetAttribute("ImmuneUntil", T0 + 8)
			expect(c.PC._tailThreatened()).toBe(false)
			c.Clock.advance(8)
			expect(c.PC._tailThreatened()).toBe(true)
			c.h.localPlayer:SetAttribute("ImmuneUntil", 0)
			expect(c.PC._tailThreatened()).toBe(true)
		end)

		it(
			"file entièrement en Guard Links (3 Nebbies, Lead Trio) : jamais coupable, pas d'alerte",
			function()
				local c = setup()
				arm(c, 3)
				expect(c.PC._tailThreatened()).toBe(false)
				c.WSC.lineLength = function()
					return 4
				end
				expect(c.PC._tailThreatened()).toBe(true)
				-- Guard Links du serveur (attribut) : 5 → une file de 4 est protégée
				c.h.localPlayer:SetAttribute("GuardLinks", 5)
				expect(c.PC._tailThreatened()).toBe(false)
				c.WSC.lineLength = function()
					return 6
				end
				expect(c.PC._tailThreatened()).toBe(true)
			end
		)

		it("seuls les nœuds au-delà des Guard Links comptent", function()
			local c = setup()
			local head, other = arm(c, 6)
			-- nœuds 1-3 (Guard Links) près de la tête, 4-6 loin derrière (40+ studs)
			local nodes = {}
			for i = 1, 6 do
				local back = if i <= 3 then 2 * i else 40 + 2 * i
				nodes[i] = Vector3.new(head.X - back, 3, head.Z)
			end
			c.CR.nodePositions = function()
				return nodes
			end
			-- rival près des Guard Links seulement : rien à couper à sa portée
			placeAt(other, Vector3.new(head.X - 4, 3, head.Z + 3))
			expect(c.PC._tailThreatened()).toBe(false)
			-- rival près du nœud 5 (queue coupable)
			placeAt(other, Vector3.new(nodes[5].X, 3, nodes[5].Z + 5))
			expect(c.PC._tailThreatened()).toBe(true)
			-- amélioration Garde du profil (repli sans attribut) : 3 + 3 = 6 → plus rien de coupable
			c.h:fireClient(
				REMOTES .. "DataPatch",
				{ upgrades = { conga = 0, stride = 0, lure = 0, perches = 2, guard = 3 } }
			)
			c.h:settle(1)
			expect(c.PC._tailThreatened()).toBe(false)
		end)
	end)
end
