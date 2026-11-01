--!nocheck
-- Correctifs r5 « panneaux à la manette » (PanelController, Panels/Collection), client console
-- complet (Main.client, manette seule) :
--   * plus de « ✕ puis sélection effacée = fenêtre d'achat » deviné pour TOUS les boutons : Acheter
--     d'Améliorer (aucune fenêtre Roblox) puis un effacement → sélection rendue dans les 3 images ;
--     seules les retenues explicites (Boutique, Équipage : PanelController.holdSelection) et le
--     menu du système laissent la sélection vide
--   * PanelNavGuard couvre aussi la croix ← : sans sélection, ← panneau ouvert est absorbée et la
--     sélection rendue (le suivi de quête derrière la fenêtre ne bouge pas)
--   * ○ recule d'un niveau dans la Réserve (Panel.onBack) : libération armée → désarmée ; mode
--     sélection → annulé, sélection rendue sur « Sélectionner » ; ○ suivant → fermeture
local roblox = require("@lune/roblox")
local Gamepad = require("../harness/Gamepad")
local Layout = require("../harness/Layout")
local ApiAudit = require("../harness/ApiAudit")

local Enum = roblox.Enum

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000
	local TODAY = math.floor(T0 / 86400)
	local K = Enum.KeyCode
	local PASS_ID = 777001

	local function neb(s, st, lk)
		return { s = s, f = 0, v = 0, st = st or 1, lk = lk }
	end

	local function profile(over)
		local nebbies = {}
		for i = 1, 12 do
			nebbies["u" .. i] = neb((i % 5) + 1)
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

	local function boot(over)
		local h = Harness.new({ mode = "client", console = true })
		h.localPlayer.LocaleId = "en-us"
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local Monetization = h:require("ReplicatedStorage.Shared.Config.Monetization")
		Monetization.Passes.VIPStar.id = PASS_ID
		ApiAudit.start()
		h:boot()
		h:fireClient(REMOTES .. "DataSnapshot", profile(over))
		h:step(1 / 60, 30)
		h:settle(3)
		local c = {
			h = h,
			Clock = Clock,
			PC = h:require(CLIENT .. "Controllers.PanelController"),
			Input = h:require(CLIENT .. "Controllers.InputController"),
			sounds = {},
			quest = 0,
		}
		local Audio = h:require(CLIENT .. "Controllers.AudioController")
		local play = Audio.play
		Audio.play = function(name, ...)
			table.insert(c.sounds, name)
			return play(name, ...)
		end
		c.Input.QuestToggled:Connect(function()
			c.quest += 1
		end)
		return c
	end

	local function finish(c)
		expect(table.concat(ApiAudit.stop(), "\n")).toBe("")
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

	local function inside(c)
		local s = selected(c)
		return s ~= nil and s:IsDescendantOf(window(c))
	end

	local function openFresh(c, name, tab)
		c.PC.close()
		frames(c, 8)
		c.h.game.GuiService.SelectedObject = nil
		c.PC.open(name, if tab then { tab = tab } else nil)
		frames(c, 8)
		Layout.apply(c.h)
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

	-- =============================================================================================
	describe("Fix r5 panneaux › sélection effacée après ✕ : seules les retenues explicites", function()
		it("Acheter d'Améliorer (aucune fenêtre Roblox) puis effacement : rendue en 3 images", function()
			local c = boot()
			openFresh(c, "Upgrades")
			local buy = selected(c)
			expect(buy ~= nil and buy.Name == "Buy").toBe(true)
			Gamepad.tap(c.h, K.ButtonA)
			expect(#sent(c, "BuyUpgrade")).toBe(1)
			expect(#c.h.log.prompts).toBe(0)
			-- la sélection s'efface (pavé tactile, menu refermé…) juste après ✕ : aucune fenêtre
			-- Roblox ne tient la manette → rendue, le stick gauche ne promène pas le personnage
			c.h.game.GuiService.SelectedObject = nil
			frames(c, 3)
			expect(inside(c)).toBe(true)
			expect(selected(c)).toBe(buy)
			finish(c)
		end)

		it("Boutique : la fenêtre d'achat (retenue explicite) laisse la sélection vide", function()
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
			c.h.game.MarketplaceService.PromptGamePassPurchaseFinished:Fire(c.h.localPlayer, PASS_ID, false)
			frames(c, 2)
			expect(selected(c)).toBe(buy)
			finish(c)
		end)
	end)

	-- =============================================================================================
	describe("Fix r5 panneaux › croix ← sans sélection, panneau ouvert", function()
		it("absorbée par PanelNavGuard : sélection rendue, suivi de quête intact", function()
			local c = boot()
			openFresh(c, "Upgrades")
			local first = selected(c)
			expect(inside(c)).toBe(true)
			c.h.game.GuiService.SelectedObject = nil
			expect(Gamepad.tap(c.h, K.DPadLeft)).toBe("PanelNavGuard")
			expect(c.quest).toBe(0)
			expect(selected(c)).toBe(first)
			-- avec une sélection, ← navigue dans la fenêtre (le moteur la traite avant)
			Gamepad.tap(c.h, K.DPadLeft)
			expect(inside(c)).toBe(true)
			expect(c.quest).toBe(0)
			-- panneau fermé : ← reprend le suivi de quête
			c.PC.close()
			frames(c, 8)
			c.h.game.GuiService.SelectedObject = nil
			Gamepad.tap(c.h, K.DPadLeft)
			expect(c.quest).toBe(1)
			finish(c)
		end)
	end)

	-- =============================================================================================
	describe("Fix r5 panneaux › ○ dans la Réserve recule d'un niveau", function()
		local function collection(c)
			return c.h:require(CLIENT .. "UI.Panels.Collection")
		end

		it(
			"mode sélection : ○ l'annule et rend la sélection à « Sélectionner » ; ○ suivant ferme",
			function()
				local c = boot()
				openFresh(c, "Collection", "stash")
				local Collection = collection(c)
				local select = selected(c)
				expect(select.Name).toBe("Select")
				Gamepad.tap(c.h, K.ButtonA)
				frames(c, 2)
				expect(Collection._state().selectMode).toBe(true)
				-- deux Nebbies choisis à ✕
				local grid = Collection._state().grid
				local picked = 0
				for _, cell in grid:cells() do
					if cell.Visible and picked < 2 then
						c.h.game.GuiService.SelectedObject = cell.Hit
						frames(c, 1)
						Gamepad.tap(c.h, K.ButtonA)
						frames(c, 1)
						picked += 1
					end
				end
				expect(Collection._state().selectedCount).toBe(2)
				table.clear(c.sounds)
				Gamepad.tap(c.h, K.ButtonB)
				frames(c, 2)
				expect(c.PC.current()).toBe("Collection")
				expect(Collection._state().selectMode).toBe(false)
				expect(Collection._state().selectedCount).toBe(0)
				expect(selected(c)).toBe(select)
				expect(table.find(c.sounds, "Back") ~= nil).toBe(true)
				-- plus rien à annuler : ○ ferme la Collection
				Gamepad.tap(c.h, K.ButtonB)
				frames(c, 8)
				expect(c.PC.current()).toBeNil()
				finish(c)
			end
		)

		it("libération armée : ○ la désarme sans fermer ; ○ suivant ferme", function()
			local c = boot()
			openFresh(c, "Collection", "stash")
			local Collection = collection(c)
			local grid = Collection._state().grid
			local cell = nil
			for _, candidate in grid:cells() do
				if candidate.Visible then
					cell = candidate
					break
				end
			end
			c.h.game.GuiService.SelectedObject = cell.Hit
			frames(c, 1)
			Gamepad.tap(c.h, K.ButtonA)
			frames(c, 1)
			expect(Collection._state().focusUid ~= nil).toBe(true)
			local release = c.PC.page("Collection").Body.Tab_stash.Actions.Release
			c.h.game.GuiService.SelectedObject = release
			frames(c, 1)
			Gamepad.tap(c.h, K.ButtonA)
			frames(c, 1)
			expect(Collection._state().armed).toBe(true)
			Gamepad.tap(c.h, K.ButtonB)
			frames(c, 2)
			expect(c.PC.current()).toBe("Collection")
			expect(Collection._state().armed).toBe(false)
			expect(#sent(c, "Release")).toBe(0)
			expect(inside(c)).toBe(true)
			Gamepad.tap(c.h, K.ButtonB)
			frames(c, 8)
			expect(c.PC.current()).toBeNil()
			expect(#sent(c, "Release")).toBe(0)
			finish(c)
		end)

		it("hors de la Réserve (Forge) : ○ ferme comme avant", function()
			local c = boot()
			openFresh(c, "Collection", "forge")
			Gamepad.tap(c.h, K.ButtonB)
			frames(c, 8)
			expect(c.PC.current()).toBeNil()
			finish(c)
		end)
	end)
end
