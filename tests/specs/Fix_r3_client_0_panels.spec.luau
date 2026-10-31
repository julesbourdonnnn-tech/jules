--!nocheck
-- Correctifs QA tour 3, paquet client r3-client-0 (PanelController) sur le VRAI client console :
--   * sélection de repli = bouton de l'onglet AFFICHÉ (pas le premier onglet) : Collection ouverte
--     sur Atlas / Guide, Calendrier réclamé à ✕ (bouton masqué) puis ✕ encore → on reste sur le
--     Calendrier (l'animation de la carte retournée n'est pas manquée)
--   * listes en lecture seule (Atlas, Guide, aperçu de la Supernova) : la croix ↑ / ↓ qui ne déplace
--     pas la sélection fait défiler la liste (≈ 70 % de sa hauteur) au lieu de « Bump » +
--     « listEnd » ; « Bump » + « listEnd » seulement au vrai bout de la liste
local roblox = require("@lune/roblox")
local Gamepad = require("../harness/Gamepad")
local Layout = require("../harness/Layout")
local ApiAudit = require("../harness/ApiAudit")

local Enum = roblox.Enum
local CFrame = roblox.CFrame

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000
	local TODAY = math.floor(T0 / 86400)
	local K = Enum.KeyCode

	local function neb(s, st, lk)
		return { s = s, f = 0, v = 0, st = st or 1, lk = lk }
	end

	-- Profil riche (comme Console_panels) : Atlas débloqué, Calendrier réclamable
	local function profile(over)
		local nebbies = {}
		for i = 1, 24 do
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
			quests = {
				day = TODAY,
				list = {
					{ id = 1, p = 3, done = false, claimed = false },
					{ id = 2, p = 10, done = true, claimed = false },
					{ id = 3, p = 1, done = true, claimed = true },
				},
				rerolls = 0,
				starClaimed = false,
			},
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
		local c = { h = h, Clock = Clock, sounds = {}, played = {} }
		local Audio = h:require(CLIENT .. "Controllers.AudioController")
		local play = Audio.play
		Audio.play = function(name, ...)
			table.insert(c.sounds, name)
			return play(name, ...)
		end
		ApiAudit.start()
		h:boot()
		h:fireClient(REMOTES .. "DataSnapshot", profile(over))
		h:step(1 / 60, 30)
		h:settle(3)
		c.PC = h:require(CLIENT .. "Controllers.PanelController")
		c.Haptics = h:require(CLIENT .. "Util.Haptics")
		c.Haptics.Played:Connect(function(name)
			table.insert(c.played, name)
		end)
		c.WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		table.clear(c.sounds)
		return c
	end

	local function finish(c)
		expect(table.concat(ApiAudit.stop(), "\n")).toBe("")
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	local function frames(c, n, dt)
		for _ = 1, n or 3 do
			c.Clock.advance(dt or 1 / 30)
			c.h:step(dt or 1 / 30, 1)
		end
		c.h:settle(1)
	end

	-- Images avec la mise en page recalculée à chacune (positions absolues à jour)
	local function laidFrames(c, n)
		for _ = 1, n do
			Layout.apply(c.h)
			frames(c, 1)
		end
	end

	local function selected(c)
		return Gamepad.selected(c.h)
	end

	local function window(c)
		return c.h.localPlayer.PlayerGui.Panels.Safe.Window
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

	local function count(list, value)
		local n = 0
		for _, v in list do
			if v == value then
				n += 1
			end
		end
		return n
	end

	local function openFresh(c, name, tab)
		c.PC.close()
		frames(c, 8)
		c.h.game.GuiService.SelectedObject = nil
		c.PC.open(name, if tab then { tab = tab } else nil)
		frames(c, 8)
		Layout.apply(c.h)
	end

	local function goHome(c)
		local me = c.h.localPlayer
		me:SetAttribute("Slot", 1)
		local gate = c.WorldLayout.gateCFrame(1).Position
		me.Character.HumanoidRootPart.CFrame = CFrame.new(gate.X, 3, gate.Z)
	end

	-- ---------------------------------------------------------------------------------------------
	describe("Fix r3 client-0 › sélection de repli sur l'onglet affiché", function()
		it(
			"Collection ouverte sur Atlas / Guide / Perchoirs : l'onglet affiché est sélectionné",
			function()
				local c = boot()
				for _, tab in { "atlas", "guide", "perches" } do
					openFresh(c, "Collection", tab)
					expect(c.PC.currentTab("Collection")).toBe(tab)
					-- avant correction : Tab_perches (premier onglet) pendant que l'Atlas est affiché
					expect({ tab = tab, sel = selected(c).Name }).toEqual({ tab = tab, sel = "Tab_" .. tab })
				end
				-- L2 puis R2 : Collection rouverte sur son onglet mémorisé (Atlas)
				c.PC.open("Collection", { tab = "atlas" })
				frames(c, 4)
				Gamepad.tap(c.h, K.ButtonR2)
				frames(c, 4)
				expect(c.PC.current()).toBe("Goals")
				Gamepad.tap(c.h, K.ButtonL2)
				frames(c, 4)
				expect(c.PC.current()).toBe("Collection")
				expect(c.PC.currentTab("Collection")).toBe("atlas")
				expect(selected(c).Name).toBe("Tab_atlas")
				finish(c)
			end
		)

		it(
			"Calendrier réclamé à ✕ : sélection sur l'onglet Calendrier, un second ✕ y reste",
			function()
				local c = boot()
				openFresh(c, "Goals", "calendar")
				local claim = selected(c)
				expect(claim.Name).toBe("Claim")
				Gamepad.tap(c.h, K.ButtonA)
				frames(c, 2)
				expect(#sent(c, "ClaimDaily")).toBe(1)
				-- réponse du serveur : jour réclamé, le bouton « Claim » disparaît
				c.h:fireClient(REMOTES .. "DataPatch", { daily = { day = TODAY, step = 3 } }, {})
				frames(c, 4)
				Layout.apply(c.h)
				expect(claim.Visible).toBe(false)
				expect(c.PC.currentTab("Goals")).toBe("calendar")
				-- avant correction : Tab_today, et le second ✕ basculait sur Aujourd'hui
				expect(selected(c).Name).toBe("Tab_calendar")
				Gamepad.tap(c.h, K.ButtonA)
				frames(c, 4)
				expect(c.PC.currentTab("Goals")).toBe("calendar")
				expect(selected(c).Name).toBe("Tab_calendar")
				expect(selected(c):IsDescendantOf(window(c))).toBe(true)
				finish(c)
			end
		)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("Fix r3 client-0 › listes en lecture seule à la croix", function()
		it("Atlas : ↓ depuis l'onglet fait défiler la liste ; « Bump » seulement au bout", function()
			local c = boot()
			openFresh(c, "Collection", "atlas")
			local list = c.PC.page("Collection").Body.Tab_atlas.List
			expect(selected(c).Name).toBe("Tab_atlas")
			expect(list.CanvasPosition.Y).toBe(0)
			table.clear(c.sounds)
			table.clear(c.played)
			Gamepad.tap(c.h, K.DPadDown)
			laidFrames(c, 3)
			-- avant correction : canevas à 0, « Bump » et vibration « listEnd »
			expect(selected(c).Name).toBe("Tab_atlas")
			local y1 = list.CanvasPosition.Y
			expect(y1 > 0).toBe(true)
			expect(count(c.sounds, "Bump")).toBe(0)
			expect(count(c.played, "listEnd")).toBe(0)
			-- ≈ 70 % de la hauteur visible de la liste par appui
			local view = list.AbsoluteSize.Y
			expect(math.abs(y1 - 0.7 * view) < 2).toBe(true)
			-- jusqu'au bout de la liste, puis « Bump » + « listEnd »
			local bottom = -1
			for _ = 1, 40 do
				Gamepad.tap(c.h, K.DPadDown)
				laidFrames(c, 3)
				if list.CanvasPosition.Y == bottom then
					break
				end
				bottom = list.CanvasPosition.Y
			end
			expect(bottom > y1).toBe(true)
			expect(count(c.sounds, "Bump")).toBe(1)
			expect(c.played).toEqual({ "listEnd" })
			-- ↑ : la sélection monte vers l'en-tête ; une fois qu'elle ne peut plus monter, ↑ remonte
			-- la liste jusqu'en haut
			for _ = 1, 40 do
				Gamepad.tap(c.h, K.DPadUp)
				laidFrames(c, 3)
				expect(selected(c):IsDescendantOf(window(c))).toBe(true)
			end
			expect(list.CanvasPosition.Y).toBe(0)
			finish(c)
		end)

		it(
			"sélection dans la liste : le défilement s'arrête quand elle atteint le bord, puis « Bump »",
			function()
				local c = boot()
				openFresh(c, "Settings")
				-- liste verticale qui contient la sélection, suivie d'un long contenu en lecture seule
				local list = selected(c).Parent
				while
					list ~= nil
					and not (
						list.ClassName == "ScrollingFrame"
						and list.AutomaticCanvasSize == Enum.AutomaticSize.Y
					)
				do
					list = list.Parent
				end
				expect(list ~= nil).toBe(true)
				local tail = c.h.globals.Instance.new("Frame")
				tail.Name = "ReadOnlyTail"
				tail.Size = roblox.UDim2.new(1, 0, 0, 1200)
				tail.LayoutOrder = 100000
				tail.Selectable = false
				tail.Parent = list
				Layout.apply(c.h)
				-- dernier objet sélectionnable de la liste : ↓ jusqu'à ce que la sélection ne bouge plus
				local last = nil
				for _ = 1, 40 do
					Gamepad.tap(c.h, K.DPadDown)
					laidFrames(c, 3)
					if selected(c) == last then
						break
					end
					last = selected(c)
				end
				-- le moteur garde la sélection affichée dans sa liste (défilement automatique, que le
				-- harnais ne simule pas) : dernier objet en bas de la liste
				do
					local r, v = Layout.rect(last), Layout.rect(list)
					local y = list.CanvasPosition.Y + (r.y + r.h) - (v.y + v.h)
					list.CanvasPosition = roblox.Vector2.new(0, math.max(0, y))
					Layout.apply(c.h)
				end
				table.clear(c.sounds)
				table.clear(c.played)
				local function inside()
					local r, v = Layout.rect(selected(c)), Layout.rect(list)
					return r.y >= v.y - 1 and r.y + r.h <= v.y + v.h + 1
				end
				expect(inside()).toBe(true)
				local moved = 0
				for _ = 1, 20 do
					local before = list.CanvasPosition.Y
					Gamepad.tap(c.h, K.DPadDown)
					laidFrames(c, 3)
					expect(selected(c)).toBe(last)
					expect(inside()).toBe(true)
					if list.CanvasPosition.Y > before then
						moved += 1
					end
					if count(c.sounds, "Bump") > 0 then
						break
					end
				end
				expect(moved > 0).toBe(true)
				expect(count(c.sounds, "Bump")).toBe(1)
				expect(c.played).toEqual({ "listEnd" })
				finish(c)
			end
		)

		it("← / → au bord : toujours « Bump » (aucun défilement horizontal)", function()
			local c = boot()
			openFresh(c, "Collection", "perches")
			expect(selected(c).Name).toBe("Tab_perches")
			c.Clock.advance(1)
			table.clear(c.sounds)
			table.clear(c.played)
			Gamepad.tap(c.h, K.DPadLeft)
			laidFrames(c, 3)
			expect(count(c.sounds, "Bump")).toBe(1)
			expect(c.played).toEqual({ "listEnd" })
			finish(c)
		end)

		it(
			"Supernova : gains en tête de l'aperçu ; ↓ depuis « Maintenir » défile jusqu'aux colonnes",
			function()
				local c = boot()
				goHome(c)
				openFresh(c, "Supernova")
				local body = c.PC.page("Supernova").Body
				local hold = body.Hold
				local preview = body.Preview
				expect(selected(c)).toBe(hold)
				-- hauteur que le moteur mesure pour les colonnes « Garder » / « Remis à zéro » (≈ 290 px de
				-- référence) : le harnais ne mesure pas l'AutomaticSize d'un cadre sans liste
				preview.Columns.AutomaticSize = Enum.AutomaticSize.None
				preview.Columns.Size = roblox.UDim2.new(1, -8, 0, 290)
				Layout.apply(c.h)
				local function shown(obj)
					local g, v = Layout.rect(obj), Layout.rect(preview)
					return g.y + g.h <= v.y + v.h + 1 and g.y >= v.y - 1
				end
				-- bas des colonnes (« Remis à zéro » jusqu'au bout) dans la partie visible de l'aperçu
				-- (les colonnes, plus hautes que l'aperçu, n'y tiennent jamais en entier)
				local function columnsEndShown()
					local g, v = Layout.rect(preview.Columns), Layout.rect(preview)
					return g.y + g.h <= v.y + v.h + 1
				end
				-- ce que le joueur gagne est visible sans défiler, avant ce geste irréversible
				expect(preview.Gains.LayoutOrder < preview.Columns.LayoutOrder).toBe(true)
				expect(shown(preview.Gains)).toBe(true)
				expect(columnsEndShown()).toBe(false)
				table.clear(c.sounds)
				table.clear(c.played)
				for _ = 1, 10 do
					if columnsEndShown() then
						break
					end
					Gamepad.tap(c.h, K.DPadDown)
					laidFrames(c, 3)
				end
				expect(selected(c)).toBe(hold)
				expect(preview.CanvasPosition.Y > 0).toBe(true)
				expect(columnsEndShown()).toBe(true)
				expect(count(c.played, "listEnd")).toBe(0)
				finish(c)
			end
		)
	end)
end
