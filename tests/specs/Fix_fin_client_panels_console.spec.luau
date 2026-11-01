--!nocheck
-- Finition « client-panels-console » (PanelController, Panels/*, UI/Root, Util/Haptics) :
--   * textes des panneaux ≥ 18 px à la manette en anglais ET en français, chaque liste défilante
--     parcourue sur toute la hauteur de son canevas (rien n'échappe à l'audit parce qu'il est
--     hors de la partie visible d'une liste) ; équipage affiché (puces des équipiers auditées)
--   * Guide de la Collection : multiplicateurs dans la langue du joueur (« Givrée ×2,5 » en
--     français, « Frozen ×2.5 » en anglais) ; probabilités longues coupées aux « · »
--   * Équipage : noms de joueurs (puces, lignes, carte d'invitation) en AutoLocalize = false
--   * UI/Root.screen sans PlayerGui : erreur claire qui nomme Root, jamais d'attente infinie
local roblox = require("@lune/roblox")
local Gamepad = require("../harness/Gamepad")
local Layout = require("../harness/Layout")
local ApiAudit = require("../harness/ApiAudit")

local Enum = roblox.Enum
local Vector2 = roblox.Vector2

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

	local function profile(over, lang)
		local nebbies = {}
		for i = 1, (over and over.stash) or 24 do
			nebbies["u" .. i] = neb((i % 5) + 1)
		end
		nebbies.f1, nebbies.f2, nebbies.f3 = neb(2), neb(2), neb(2)
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
				lang = lang or "en",
			},
			cosmetics = { style = "default", title = "", nestTheme = "default" },
			unlocks = { styles = {}, titles = {}, themes = {} },
			weeklyBest = { week = 0, conga = 0 },
			starterKit = false,
			stats = {},
			passes = {},
		}
		for k, v in over or {} do
			if k ~= "stash" then
				p[k] = v
			end
		end
		return p
	end

	-- Client console complet (Main.client), langue au choix
	local function boot(over, opts)
		opts = opts or {}
		local lang = opts.lang or "en"
		local h = Harness.new({
			mode = "client",
			console = opts.console ~= false and not opts.touch,
			touch = opts.touch,
			viewport = opts.viewport,
		})
		h.localPlayer.LocaleId = if lang == "fr" then "fr-fr" else "en-us"
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
		if opts.audit ~= false then
			ApiAudit.start()
		end
		h:boot()
		h:fireClient(REMOTES .. "DataSnapshot", profile(over, lang))
		h:step(1 / 60, 30)
		h:settle(3)
		c.PC = h:require(CLIENT .. "Controllers.PanelController")
		c.Input = h:require(CLIENT .. "Controllers.InputController")
		c.Prefs = h:require(CLIENT .. "Util.Prefs")
		table.clear(c.sounds)
		return c
	end

	local function finish(c, audited)
		local issues = if audited == false then {} else ApiAudit.stop()
		expect(table.concat(issues, "\n")).toBe("")
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	local function window(c)
		return c.h.localPlayer.PlayerGui.Panels.Safe.Window
	end

	local function frames(c, n, dt)
		for _ = 1, n or 3 do
			c.Clock.advance(dt or 1 / 30)
			c.h:step(dt or 1 / 30, 1)
		end
		c.h:settle(1)
	end

	local function selected(c)
		return Gamepad.selected(c.h)
	end

	local function openFresh(c, name, tab)
		c.PC.close()
		frames(c, 8)
		c.h.game.GuiService.SelectedObject = nil
		c.PC.open(name, if tab then { tab = tab } else nil)
		frames(c, 8)
		Layout.apply(c.h)
	end

	-- Taille (px d'écran) du contenu d'une liste défilante, mesurée défilement à 0
	local function contentSize(scroll)
		local top = Layout.rect(scroll)
		if top == nil then
			return 0, 0
		end
		local right, bottom = top.x + top.w, top.y + top.h
		for _, d in scroll:GetDescendants() do
			local r = Layout.rect(d)
			if r ~= nil and d:IsA("GuiObject") and Layout.visible(d) then
				right = math.max(right, r.x + r.w)
				bottom = math.max(bottom, r.y + r.h)
			end
		end
		return right - top.x, bottom - top.y
	end

	-- Audit console de la fenêtre, chaque liste défilante visible parcourue sur toute sa hauteur
	local function scrolledAudit(c)
		local w = window(c)
		local found, issues = {}, {}
		local function collect()
			for _, issue in Gamepad.audit(c.h, { root = w, safeArea = false }) do
				if not found[issue] then
					found[issue] = true
					table.insert(issues, issue)
				end
			end
		end
		collect()
		Layout.apply(c.h)
		for _, scroll in w:GetDescendants() do
			if scroll.ClassName == "ScrollingFrame" and Layout.visible(scroll) then
				local r = Layout.rect(scroll)
				if r ~= nil and r.h > 1 then
					-- liste dans une liste (puces des Réglages) : la liste englobante la montre d'abord
					local outer = {}
					local cur = scroll.Parent
					while cur ~= nil and cur ~= w do
						if cur.ClassName == "ScrollingFrame" then
							table.insert(outer, 1, cur)
						end
						cur = cur.Parent
					end
					for _, o in outer do
						o.CanvasPosition = Vector2.zero
						frames(c, 1)
						Layout.apply(c.h)
						local ro, ri = Layout.rect(o), Layout.rect(scroll)
						o.CanvasPosition = Vector2.new(0, math.max(0, ri.y - ro.y))
						frames(c, 1)
						Layout.apply(c.h)
					end
					scroll.CanvasPosition = Vector2.zero
					frames(c, 1)
					Layout.apply(c.h)
					r = Layout.rect(scroll)
					local totalW, totalH = contentSize(scroll)
					local stepX, stepY = math.max(20, r.w * 0.5), math.max(20, r.h * 0.5)
					local y = 0
					while y < totalH - r.h + stepY do
						local x = 0
						while x < totalW - r.w + stepX do
							scroll.CanvasPosition = Vector2.new(x, y)
							frames(c, 1)
							Layout.apply(c.h)
							collect()
							x += stepX
						end
						y += stepY
					end
					scroll.CanvasPosition = Vector2.zero
					for _, o in outer do
						o.CanvasPosition = Vector2.zero
					end
					frames(c, 1)
				end
			end
		end
		table.sort(issues)
		return issues
	end

	local CASES = {
		{ "Upgrades" },
		{ "Supernova" },
		{ "Collection", "perches" },
		{ "Collection", "stash" },
		{ "Collection", "forge" },
		{ "Collection", "atlas" },
		{ "Collection", "guide" },
		{ "Goals", "today" },
		{ "Goals", "calendar" },
		{ "Goals", "week" },
		{ "Shop", "passes" },
		{ "Shop", "boosts" },
		{ "Shop", "codes" },
		{ "Crew" },
		{ "Settings" },
	}

	-- =============================================================================================
	describe(
		"Fin panels-console › textes ≥ 18 px en anglais et en français, listes parcourues",
		function()
			for _, lang in { "en", "fr" } do
				it(`{lang} : chaque panneau, chaque onglet, chaque liste défilée jusqu'au bout`, function()
					local c = boot({ stash = 60 }, { lang = lang })
					expect(c.Prefs.language()).toBe(lang)
					for i = 2, 4 do
						c.h:addPlayer({ userId = i, name = "P" .. i })
					end
					-- équipage avec le joueur 2 : puces des équipiers affichées dans l'onglet Équipage
					local WSC = c.h:require(CLIENT .. "Controllers.WorldStateController")
					local me = c.h.localPlayer.UserId
					WSC.crews = function()
						return { crews = { { id = 1, userIds = { me, 2 } } } }
					end
					c.h:settle(2)
					local all = {}
					for _, case in CASES do
						openFresh(c, case[1], case[2])
						expect(c.PC.current()).toBe(case[1])
						for _, issue in scrolledAudit(c) do
							table.insert(all, table.concat(case, "/") .. " : " .. issue)
						end
					end
					expect(table.concat(all, "\n")).toBe("")
					finish(c)
				end)
			end
		end
	)

	-- Téléphones à l'horizontale (échelle 0,6) : même audit, client tactile (validation r6 : seul
	-- l'onglet Objectifs était audité sur téléphone ; « +1 perchoir (gardé à la Supernova) » de la
	-- carte Perchoirs tombait à 16,3 px en 640 × 360)
	local PHONES = { Vector2.new(640, 360), Vector2.new(667, 375) }

	describe("Fin panels-console › téléphone : textes ≥ 18 px, chaque panneau, EN et FR", function()
		for _, size in PHONES do
			for _, lang in { "en", "fr" } do
				it(
					`{size.X} × {size.Y} tactile ({lang}) : chaque panneau, chaque onglet, listes défilées`,
					function()
						local c = boot({ stash = 60 }, { lang = lang, touch = true, viewport = size })
						expect(c.Prefs.language()).toBe(lang)
						local Root = c.h:require(CLIENT .. "UI.Root")
						expect(Root.scale()).toBe(0.6)
						for i = 2, 4 do
							c.h:addPlayer({ userId = i, name = "P" .. i })
						end
						local WSC = c.h:require(CLIENT .. "Controllers.WorldStateController")
						local me = c.h.localPlayer.UserId
						WSC.crews = function()
							return { crews = { { id = 1, userIds = { me, 2 } } } }
						end
						c.h:settle(2)
						local all = {}
						for _, case in CASES do
							openFresh(c, case[1], case[2])
							expect(c.PC.current()).toBe(case[1])
							for _, issue in scrolledAudit(c) do
								table.insert(all, table.concat(case, "/") .. " : " .. issue)
							end
						end
						expect(table.concat(all, "\n")).toBe("")
						finish(c)
					end
				)
			end
		end
	end)

	-- =============================================================================================
	describe("Fin panels-console › Guide de la Collection", function()
		local function guideTexts(c)
			c.PC.open("Collection", { tab = "guide" })
			frames(c, 4)
			local list = c.PC.page("Collection").Body.Tab_guide.List
			local lines = {}
			for _, child in list:GetChildren() do
				if child:IsA("TextLabel") then
					table.insert(lines, child)
				end
			end
			table.sort(lines, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			local texts = {}
			for _, label in lines do
				table.insert(texts, label.Text)
			end
			return texts, lines
		end

		it("français : multiplicateurs à la virgule (« Givrée ×2,5 »), jamais « ×2.5 »", function()
			local c = boot(nil, { lang = "fr" })
			local texts = guideTexts(c)
			local all = table.concat(texts, "\n")
			expect(string.find(all, "Givrée ×2,5", 1, true) ~= nil).toBe(true)
			expect(string.find(all, "×2.5", 1, true)).toBeNil()
			expect(string.find(all, "Géant ×3 : 0,5 %", 1, true) ~= nil).toBe(true)
			-- aucun nombre décimal anglais dans tout le Guide en français
			expect(string.match(all, "%d%.%d")).toBeNil()
			finish(c)
		end)

		it("anglais : « Frozen ×2.5 », lignes de zone courtes inchangées", function()
			local c = boot(nil, { lang = "en" })
			local texts = guideTexts(c)
			local all = table.concat(texts, "\n")
			expect(string.find(all, "Frozen ×2.5", 1, true) ~= nil).toBe(true)
			expect(
				string.find(all, "Outer Meadow — Common: 78% · Uncommon: 19% · Rare: 3%", 1, true) ~= nil
			).toBe(true)
			finish(c)
		end)

		it(
			"probabilités longues coupées aux « · », lignes suivantes en retrait, rien de perdu",
			function()
				local c = boot(nil, { lang = "fr" })
				local texts, lines = guideTexts(c)
				local found = nil
				for i, text in texts do
					if string.find(text, "Cratère — ", 1, true) == 1 then
						found = i
					end
				end
				expect(found ~= nil).toBe(true)
				local head, tail = texts[found], texts[found + 1]
				-- même contenu qu'avant, réparti sur deux lignes coupées à un « · »
				expect(head .. " · " .. tail).toBe(
					"Cratère — Peu commun : 25 % · Rare : 45 % · Épique : 23 % · Légendaire : 6,5 % · Mythique : 0,5 %"
				)
				expect(lines[found]:FindFirstChildOfClass("UIPadding")).toBeNil()
				expect(lines[found + 1]:FindFirstChildOfClass("UIPadding") ~= nil).toBe(true)
				for _, text in texts do
					expect({ text = text, short = utf8.len(text) <= 60 }).toEqual({
						text = text,
						short = true,
					})
				end
				finish(c)
			end
		)
	end)

	-- =============================================================================================
	describe("Fin panels-console › Équipage : noms de joueurs jamais traduits", function()
		it("puces des équipiers, lignes des joueurs et carte d'invitation : AutoLocalize = false", function()
			local c = boot(nil, { lang = "fr" })
			c.h:addPlayer({ userId = 2, name = "Lune" })
			c.h:addPlayer({ userId = 3, name = "Soleil" })
			local WSC = c.h:require(CLIENT .. "Controllers.WorldStateController")
			local me = c.h.localPlayer.UserId
			WSC.crews = function()
				return { crews = { { id = 1, userIds = { me, 2 } } } }
			end
			c.h:settle(2)
			c.PC.open("Crew")
			frames(c, 4)
			local page = c.PC.page("Crew")
			local chip = page:FindFirstChild("Member2", true)
			expect(chip ~= nil).toBe(true)
			expect(chip:FindFirstChild("Name").AutoLocalize).toBe(false)
			expect(page:FindFirstChild("Member" .. me, true):FindFirstChild("Name").AutoLocalize).toBe(false)
			local row = page:FindFirstChild("Player3", true)
			expect(row ~= nil).toBe(true)
			local rowName = row:FindFirstChild("Name")
			expect(rowName.Text).toBe("Soleil")
			expect(rowName.AutoLocalize).toBe(false)
			-- textes traduits par Prefs.t (titres, boutons) : inchangés
			expect(row.Invite.Label.AutoLocalize).toBe(true)
			-- carte d'invitation « Soleil t'invite ! » (hors de la fenêtre, panneau fermé)
			c.PC.close()
			frames(c, 8)
			local Crew = c.h:require(CLIENT .. "UI.Panels.Crew")
			Crew.showInvite({ inviterId = 3, expiresAt = T0 + 20 })
			frames(c, 2)
			local card = Crew._card()
			expect(string.find(card.Text.Text, "Soleil", 1, true) ~= nil).toBe(true)
			expect(card.Text.AutoLocalize).toBe(false)
			finish(c)
		end)
	end)

	-- =============================================================================================
	describe("Fin panels-console › UI/Root.screen sans PlayerGui", function()
		it("erreur claire qui nomme Root et l'écran, aucune attente infinie", function()
			local h = Harness.new({ mode = "client" })
			local Root = h:require(CLIENT .. "UI.Root")
			Root.PlayerGuiWait = 0.05
			h.localPlayer.PlayerGui.Parent = nil
			local ok, err = pcall(Root.screen, "HUD", 10)
			expect(ok).toBe(false)
			expect(string.find(tostring(err), "[Root]", 1, true) ~= nil).toBe(true)
			expect(string.find(tostring(err), "PlayerGui", 1, true) ~= nil).toBe(true)
			expect(string.find(tostring(err), "HUD", 1, true) ~= nil).toBe(true)
			expect(table.concat(h:warnings(), "\n")).toBe("")
		end)

		it("PlayerGui présent : écran créé tout de suite (sans attendre)", function()
			local h = Harness.new({ mode = "client" })
			local Root = h:require(CLIENT .. "UI.Root")
			local gui = Root.screen("HUD", 10)
			expect(gui.Parent).toBe(h.localPlayer:FindFirstChildOfClass("PlayerGui"))
			expect(gui.Safe ~= nil).toBe(true)
			expect(table.concat(h:warnings(), "\n")).toBe("")
			expect(table.concat(h.errors, "\n")).toBe("")
		end)
	end)
end
