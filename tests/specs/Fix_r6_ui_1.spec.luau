--!nocheck
-- Finition r6 (fixer r6-ui-1) : Objectifs (src/client/UI/Panels/Goals.luau) lisible sur téléphone.
--   Avant : l'audit de texte de Fix_fin_client_panels_console ne tournait qu'en console 1920 × 1080.
--   Sur un téléphone 640 × 360 (échelle 0,6), la face du jour 7 du Calendrier écrivait
--   « Glimmerwhale + 100 Stardust » à 16 px de référence (17 px en 667 × 375, 12 px en 568 × 320) :
--   le seul mot « Glimmerwhale » ne tient pas à 18 px dans une face de ≈ 90 px, alors que l'icône
--   montre déjà le Nebby ; la récompense d'une quête du jour (une ligne de 26 px) écrivait
--   « ≈ 21,6 k Glow + 40 Stardust » à 17,5 px en 640 × 360 (≈ 13 px en 568 × 320) ; en 568 × 320
--   et en français, « Aujourd'hui » (étiquette du jour) tombait à 16 px.
--   Maintenant : face d'un jour à Nebby = icône + reste court (« +100 ✦ ») ; le nom de l'espèce
--   n'est écrit que s'il est toute la récompense (jour 5 « Daybreak Puff », qui tient) ; récompense
--   de quête sur deux lignes (44 px, au-dessus du bas de la carte). Audit EN / FR de Fix_fin_client_panels_console (listes parcourues sur toute leur
--   hauteur) repris sur un client tactile en 640 × 360 et 667 × 375 ; en 568 × 320, les
--   récompenses (quêtes, faces du Calendrier) seulement : « Aujourd'hui » (≈ 5 em) n'y tient pas à
--   18 px dans une face de ≈ 85 px, même sur toute sa largeur (libellé français à trancher).
local roblox = require("@lune/roblox")
local Gamepad = require("../harness/Gamepad")
local Layout = require("../harness/Layout")
local ApiAudit = require("../harness/ApiAudit")

local Vector2 = roblox.Vector2

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000
	local TODAY = math.floor(T0 / 86400)

	-- téléphones à l'horizontale (échelle 0,6) : audit complet de l'onglet
	local PHONES = {
		Vector2.new(640, 360),
		Vector2.new(667, 375),
	}
	-- iPhone SE (1re génération) : récompenses seulement (voir le dernier bloc)
	local SMALLEST = Vector2.new(568, 320)

	local function neb(s)
		return { s = s, f = 0, v = 0, st = 1 }
	end

	-- profil de Fix_fin_client_panels_console : revenu passif 120 / s (« ≈ 21,6 k Glow »), quêtes
	-- du jour en cours / à réclamer / réclamée ; calendrier au jour `step` (prochain jour à réclamer)
	local function profile(lang, over)
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
				lang = lang,
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

	-- Client tactile complet (Main.client) sur un téléphone de `size` px
	local function boot(size, lang, over)
		local h = Harness.new({ mode = "client", touch = true, viewport = size })
		h.localPlayer.LocaleId = if lang == "fr" then "fr-fr" else "en-us"
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		ApiAudit.start()
		h:boot()
		h:fireClient(REMOTES .. "DataSnapshot", profile(lang, over))
		h:step(1 / 60, 30)
		h:settle(3)
		local c = {
			h = h,
			Clock = Clock,
			PC = h:require(CLIENT .. "Controllers.PanelController"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			Root = h:require(CLIENT .. "UI.Root"),
		}
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

	local function window(c)
		return c.h.localPlayer.PlayerGui.Panels.Safe.Window
	end

	local function openFresh(c, name, tab)
		c.PC.close()
		frames(c, 8)
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

	-- Audit de texte de la fenêtre (Gamepad.audit, sans zone sûre TV), chaque liste défilante
	-- visible parcourue sur toute sa hauteur (même passe que Fix_fin_client_panels_console)
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
					frames(c, 1)
				end
			end
		end
		table.sort(issues)
		return issues
	end

	local function goals(c)
		return c.h:require(CLIENT .. "UI.Panels.Goals")
	end

	-- =============================================================================================
	describe(
		"Fix r6 ui-1 › Objectifs : textes ≥ 18 px sur téléphone, en anglais et en français",
		function()
			for _, size in PHONES do
				for _, lang in { "en", "fr" } do
					it(`{size.X} × {size.Y} tactile ({lang}) : Aujourd'hui, Calendrier, Semaine`, function()
						local c = boot(size, lang)
						expect(c.Prefs.language()).toBe(lang)
						expect(c.Root.scale()).toBe(0.6)
						local all = {}
						for _, tab in { "today", "calendar", "week" } do
							openFresh(c, "Goals", tab)
							expect(c.PC.current()).toBe("Goals")
							expect(c.PC.currentTab("Goals")).toBe(tab)
							for _, issue in scrolledAudit(c) do
								table.insert(all, `Goals/{tab} : {issue}`)
							end
						end
						expect(table.concat(all, "\n")).toBe("")
						finish(c)
					end)

					it(
						`{size.X} × {size.Y} tactile ({lang}) : jour du calendrier « aujourd'hui »`,
						function()
							-- faces à Nebby (jours 5 et 7) « aujourd'hui » : étiquette la plus longue, face
							-- surlignée, nom de l'espèce ou reste court ; le jour 2 l'est dans le test précédent
							local all = {}
							for _, step in { 5, 7 } do
								local c = boot(size, lang, { daily = { day = TODAY - 1, step = step } })
								openFresh(c, "Goals", "calendar")
								local G = goals(c)
								expect(G._dayCards[step].day.Text).toBe(c.Prefs.t("calendar.today"))
								for _, issue in scrolledAudit(c) do
									table.insert(all, `jour {step} : {issue}`)
								end
								finish(c)
							end
							expect(table.concat(all, "\n")).toBe("")
						end
					)
				end
			end
		end
	)

	-- =============================================================================================
	describe("Fix r6 ui-1 › faces du Calendrier à Nebby : l'icône montre l'espèce", function()
		for _, lang in { "en", "fr" } do
			it(
				`{lang} : jour 7 « +100 ✦ » (sans le nom de l'espèce), jour 5 « Daybreak Puff »`,
				function()
					local c = boot(Vector2.new(640, 360), lang)
					openFresh(c, "Goals", "calendar")
					local G = goals(c)
					local day7, day5 = G._dayCards[7], G._dayCards[5]
					-- jour 7 : Nebby de la rotation (icône) + Stardust en court
					expect(day7.icon.Visible).toBe(true)
					expect(day7.glyph.Visible).toBe(false)
					expect(day7.reward.Text).toBe("+100 ✦")
					expect(string.find(day7.reward.Text, "Stardust", 1, true)).toBeNil()
					-- jour 5 : l'espèce est toute la récompense, son nom reste écrit sous l'icône
					expect(day5.icon.Visible).toBe(true)
					expect(day5.reward.Text).toBe("Daybreak Puff")
					-- jours sans Nebby : texte complet inchangé
					expect(G._dayCards[2].icon.Visible).toBe(false)
					expect(G._dayCards[2].reward.Text).toBe(
						c.Prefs.t("calendar.reward.stardust", { amount = 50 })
					)
					expect(G._dayCards[4].reward.Text).toBe(
						c.Prefs.t("calendar.reward.stardust", { amount = 150 })
					)
					finish(c)
				end
			)
		end

		it(
			"quêtes du jour : texte complet (« ≈ 21,6 k Glow + 40 Stardust », Stardust en toutes lettres)",
			function()
				local c = boot(Vector2.new(640, 360), "fr")
				openFresh(c, "Goals", "today")
				local G = goals(c)
				local Quests = c.h:require("ReplicatedStorage.Shared.Config.Quests")
				local P = c.Prefs
				for slot, card in G._questCards do
					local q = Quests.Daily[({ 1, 2, 3 })[slot]]
					local reward = Quests.DailyTiers[q.tier]
					local glow = P.t("common.approx", { amount = P.number(reward.idleSeconds * 120) })
					local expected = P.t("calendar.reward.glow", { amount = glow })
						.. " + "
						.. P.t("calendar.reward.stardust", { amount = P.number(reward.stardust) })
					expect(card.reward.Text).toBe(expected)
				end
				local first = G._questCards[1].reward.Text
				expect(string.find(first, "21,6", 1, true) ~= nil).toBe(true)
				expect(string.find(first, "40 Stardust", 1, true) ~= nil).toBe(true)
				finish(c)
			end
		)
	end)

	-- =============================================================================================
	describe("Fix r6 ui-1 › récompense d'une quête du jour sur deux lignes", function()
		for _, size in { Vector2.new(640, 360), Vector2.new(1280, 720), Vector2.new(1920, 1080) } do
			it(
				`{size.X} × {size.Y} : 44 px de haut, au-dessus du bas de la carte, sans chevaucher`,
				function()
					local c = boot(size, "fr")
					openFresh(c, "Goals", "today")
					local G = goals(c)
					for slot, card in G._questCards do
						local reward = card.reward
						expect(reward.TextWrapped).toBe(true)
						expect(reward.Size.Y.Offset >= 44).toBe(true)
						local r, f = Layout.rect(reward), Layout.rect(card.frame)
						local k = r.k
						-- dans la carte, au moins 4 px de référence au-dessus du bas
						expect({ slot = slot, inside = r.y >= f.y - 0.5 and r.y + r.h <= f.y + f.h - 4 * k }).toEqual({
							slot = slot,
							inside = true,
						})
						-- ni la description, ni la barre, ni la progression, ni les boutons
						for _, name in { "title", "desc", "bar", "progress", "claim", "reroll", "check" } do
							local o = if Layout.visible(card[name]) then Layout.rect(card[name]) else nil
							local overlap = o ~= nil
								and r.x < o.x + o.w - 0.5
								and o.x < r.x + r.w - 0.5
								and r.y < o.y + o.h - 0.5
								and o.y < r.y + r.h - 0.5
							expect({ slot = slot, other = name, overlap = overlap }).toEqual({
								slot = slot,
								other = name,
								overlap = false,
							})
						end
					end
					finish(c)
				end
			)
		end
	end)

	-- =============================================================================================
	describe("Fix r6 ui-1 › 568 × 320 : récompenses ≥ 18 px", function()
		for _, lang in { "en", "fr" } do
			it(
				`{lang} : quêtes du jour (deux lignes) et faces du Calendrier (jour 7 « +100 ✦ »)`,
				function()
					local all = {}
					for _, step in { 2, 7 } do
						local c = boot(SMALLEST, lang, { daily = { day = TODAY - 1, step = step } })
						expect(c.Root.scale()).toBe(0.6)
						for _, tab in { "today", "calendar" } do
							openFresh(c, "Goals", tab)
							for _, issue in scrolledAudit(c) do
								if string.find(issue, ".Reward ", 1, true) then
									table.insert(all, `jour {step}, Goals/{tab} : {issue}`)
								end
							end
						end
						finish(c)
					end
					expect(table.concat(all, "\n")).toBe("")
				end
			)
		end
	end)
end
