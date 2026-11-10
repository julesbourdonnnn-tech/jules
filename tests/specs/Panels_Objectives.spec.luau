--!nocheck
-- Panels/Objectives (paquet client-panels ; GDD §7.3, §7.4, §3 ; docs/04 §13.6) : Aujourd'hui (3
-- objectifs, « Réclamer » par défaut, relance gratuite une fois par jour), Plop (jours au total,
-- paliers), Accueil (tant qu'il n'est pas fini), UiSeen("objectives") à la première ouverture. Un
-- bouton refusé ne part jamais au serveur. Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")

local Enum = roblox.Enum

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local NOW = 1800000000
	local DAY = math.floor(NOW / 86400)

	local function objectives(list, rerolls)
		return { day = DAY, list = list, rerolls = rerolls or 0, allClaimed = false }
	end

	local function setup(profile)
		local h = TvAudit.client({ profile = profile, now = NOW })
		return {
			h = h,
			PC = TvAudit.mod(h, "UI.PanelController"),
			Obj = TvAudit.mod(h, "UI.Panels.Objectives"),
		}
	end

	local function clean(c)
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	local function page(c)
		return c.PC.window("Objectives").Body.Page_today
	end

	local function press(c, obj)
		TvAudit.tick(c.h, 0.5)
		c.h.game.GuiService.SelectedObject = obj
		Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
	end

	describe("Panels/Objectives", function()
		it(
			"« Réclamer » disponible sélectionné d'office ; ClaimObjective(case) ; UiSeen une seule fois",
			function()
				local c = setup({
					objectives = objectives({
						{ id = 1, p = 12, done = false, claimed = false },
						{ id = 7, p = 2, done = true, claimed = false },
						{ id = 14, p = 0, done = false, claimed = false },
					}),
				})
				c.PC.open("Objectives")
				local p = page(c)
				expect(c.h.game.GuiService.SelectedObject).toBe(p.Card2.Action)
				expect(c.Obj._cardMode(2)).toBe("claim")
				expect(p.Card1.Text.Text).toBe("Press 30 squishies")
				expect(p.Card1.Progress.Text).toBe("12 / 30")
				expect(p.Card2.Reward.Text).toBe("+6 min of coins")
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				expect(TvAudit.sent(c.h, "ClaimObjective")[1][1]).toBe(2)
				c.PC.closeAll()
				TvAudit.tick(c.h, 0.5)
				c.PC.open("Objectives")
				local seen = 0
				for _, args in TvAudit.sent(c.h, "UiSeen") do
					if args[1] == "objectives" then
						seen += 1
					end
				end
				expect(seen).toBe(1)
				clean(c)
			end
		)

		it(
			"relance : une par jour, seulement sur un objectif pas fait ; épuisée : refusée sans envoi",
			function()
				local list = {
					{ id = 1, p = 0, done = false, claimed = false },
					{ id = 7, p = 0, done = false, claimed = false },
					{ id = 14, p = 0, done = false, claimed = true },
				}
				local c = setup({ objectives = objectives(list, 0) })
				c.PC.open("Objectives")
				local p = page(c)
				expect(c.Obj._cardMode(1)).toBe("reroll")
				expect(c.Obj._cardMode(3)).toBe("claimed")
				press(c, p.Card1.Action)
				expect(TvAudit.sent(c.h, "RerollObjective")[1][1]).toBe(1)
				local c2 = setup({ objectives = objectives(list, 1) })
				c2.PC.open("Objectives")
				expect(c2.Obj._cardMode(1)).toBe("noReroll")
				press(c2, page(c2).Card1.Action)
				press(c2, page(c2).Card3.Action) -- déjà réclamé
				expect(#TvAudit.sent(c2.h, "RerollObjective")).toBe(0)
				expect(#TvAudit.sent(c2.h, "ClaimObjective")).toBe(0)
				clean(c)
				clean(c2)
			end
		)

		it(
			"les 3 réclamés : « Goutte chanceuse » ; Plop : jours au total et paliers ; Accueil fini : onglet caché",
			function()
				local c = setup({
					objectives = objectives({
						{ id = 1, p = 30, done = true, claimed = true },
						{ id = 7, p = 2, done = true, claimed = true },
						{ id = 14, p = 1, done = true, claimed = true },
					}),
					plopDays = 7,
					lastFeedDay = DAY,
					onboarding = { step = 11, done = true, demoDone = true },
				})
				c.PC.open("Objectives")
				expect(page(c).AllDone.Visible).toBe(true)
				expect(c.Obj.tabs()).toEqual({ "today", "plop" })
				c.Obj.setTab("plop")
				local plop = c.PC.window("Objectives").Body.Page_plop
				expect(plop.Total.Text).toBe("7 days in total")
				expect(plop.Today.Text).toContain("full")
				-- coche DESSINÉE (règle 18, lot B3, D17) : « ✓ » absent des polices
				expect(plop.Cell5.Status:GetAttribute("Icon")).toBe("check") -- jour 7 atteint
				expect(plop.Cell6.Status:GetAttribute("Icon")).toBe("") -- jour 10
				-- un nouveau : l'onglet Accueil existe et montre les étapes faites
				local c2 = setup({ onboarding = { step = 3, done = false, demoDone = false } })
				c2.PC.open("Objectives", "onboarding")
				expect(c2.Obj.currentTab()).toBe("onboarding")
				local steps = c2.PC.window("Objectives").Body.Page_onboarding
				expect(steps.Cell3.Status:GetAttribute("Icon")).toBe("check")
				expect(steps.Cell4.Status:GetAttribute("Icon")).toBe("")
				clean(c)
				clean(c2)
			end
		)

		it("objectifs abîmés (ids inconnus, NaN, chaînes) : aucune erreur, cartes cachées", function()
			local c = setup({
				objectives = { day = DAY, list = { { id = 999 }, "x", { id = 1, p = 0 / 0 } }, rerolls = "a" },
				plopDays = -3,
				onboarding = 5,
			})
			for _, tab in { "today", "plop", "onboarding" } do
				c.PC.open("Objectives", tab)
				TvAudit.tick(c.h, 0.5)
			end
			expect(page(c).Card1.Visible).toBe(false)
			expect(page(c).Card3.Visible).toBe(true)
			clean(c)
		end)
	end)

	describe("Panels/Objectives › v2.0 (lot B3, piste, Défis, Carnet)", function()
		local UpgradeScreen = require("../harness/UpgradeScreen")
		local S = UpgradeScreen.new(T.Harness)
		local V2 = UpgradeScreen.V2_ALL
		local WEEK = 604800
		local EPOCH = 345600
		local PERIOD = 2975 -- semaine de 1800000000 (vendredi) : cosmétique n° 8, Coussins « Nuage rose »
		local function monday(w)
			return EPOCH + w * WEEK
		end

		-- profil v2 : piste de la semaine (9 points, paliers 1-4 réclamés), 3 Défis, 600 niveaux achetés
		local function v2profile(edit)
			local p = {
				version = 2,
				onboarding = { step = 11, done = true, demoDone = true },
				weeklyTrack = {
					period = PERIOD,
					points = 9,
					claimed = { 15 },
					won = { 0 },
					firstPeriodEnd = monday(2970),
					challenges = {
						{ id = 1, p = 1, done = false },
						{ id = 6, p = 1, done = true },
						{ id = 12, p = 10, done = false },
					},
					play = { 0, 0, 0, 0, 0, 0, 0 },
					playDay = 0,
				},
				carnet = { 15 },
				stats = { upgradesBought = 600, splorches = 3 },
			}
			if edit then
				edit(p)
			end
			return p
		end

		local function v2client(opts)
			opts = opts or {}
			local c = S.client({ profile = v2profile(opts.edit), lang = opts.lang })
			if opts.flags ~= false then
				S.event(c, opts.flags or V2)
			end
			c.Obj = TvAudit.mod(c.h, "UI.Panels.Objectives")
			return c
		end

		local function body(c)
			return c.PC.window("Objectives").Body
		end

		-- texte d'un libellé sur une ligne : les mots tenus ensemble (« {_} ») sont coupés par UI/Text
		-- à la largeur de la boîte, que le harnais sans mise en page laisse à 100 px
		local function flat(label)
			return (string.gsub(label.Text, "\n", " "))
		end

		local function openTab(c, tab)
			c.PC.closeAll()
			TvAudit.tick(c.h, 0.5)
			c.PC.open("Objectives", tab)
			TvAudit.tick(c.h, 0.5)
		end

		local function tabButtons(c)
			local out = {}
			for _, b in body(c).Tabs.Strip:GetChildren() do
				if b:IsA("TextButton") and b.Visible then
					table.insert(out, b.Name)
				end
			end
			table.sort(out)
			return out
		end

		it(
			"piste : points, jours restants, 12 paliers et leur récompense d'avance, réclamés cochés, prochain palier ; 1er palier sélectionné",
			function()
				local c = v2client()
				openTab(c, "track")
				expect(c.Obj.currentTab()).toBe("track")
				expect(c.Obj.tabs()).toEqual({ "today", "track", "carnet", "plop" })
				local page = body(c).Page_track
				expect(page.Visible).toBe(true)
				expect(page.Points.Text).toBe("9 / 24 points")
				expect(page.Ends.Text).toBe("Ends in 3 d") -- lundi 00:00 UTC suivant : 2 j 16 h
				expect(page.Tier1.Head.Text).toBe("Tier 1")
				expect(page.Tier1.Reward.Text).toBe("+2 Confetti")
				expect(page.Tier4.Reward.Text).toBe("Lucky Drop")
				expect(page.Tier11.Reward.Text).toBe("+6 Confetti")
				expect(page.Tier12.Reward.Text).toBe("Pink Cloud Cushions") -- cosmétique de la période
				for i = 1, 4 do
					expect(page["Tier" .. i].Check:GetAttribute("Icon")).toBe("check")
				end
				expect(page.Tier5.Check:GetAttribute("Icon")).toBe("")
				expect(page.Tier5.BackgroundColor3).toBe(TvAudit.mod(c.h, "UI.Panels.Widgets").Colors.Accent)
				expect(S.selected(c)).toBe(page.Tier1)
				-- aucun bouton « Réclamer » : le serveur réclame tout seul ; ✕ sur un palier n'envoie rien
				S.select(c, page.Tier5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				TvAudit.tick(c.h, 0.5)
				expect(#TvAudit.sent(c.h, "ClaimObjective")).toBe(0)
				expect(#TvAudit.sent(c.h, "RerollObjective")).toBe(0)
				S.clean(c, expect)
			end
		)

		it(
			"Défis : progression et fait (coche) ; récompenses de la semaine : celle de la période puis la semaine prochaine, dans 6 semaines, déjà gagnée",
			function()
				local c = v2client()
				openTab(c, "track")
				local page = body(c).Page_track
				expect(page.ChallengesTitle.Visible).toBe(true)
				expect(page.Challenge1.Label.Text).toBe("Do 2 Grand Splorches")
				expect(page.Challenge1.Progress.Text).toBe("1 / 2")
				expect(page.Challenge1.Check:GetAttribute("Icon")).toBe("")
				expect(page.Challenge2.Progress.Text).toBe("1 / 1")
				expect(page.Challenge2.Check:GetAttribute("Icon")).toBe("check")
				expect(page.Challenge3.Progress.Text).toBe("10 / 30")
				local soon = page.Soon
				expect(soon.Title.Text).toBe("Weekly cosmetics")
				expect(soon.Name1.Text).toBe("Pink Cloud Cushions")
				expect(soon.Status1.Text).toBe("Tier 12")
				expect(soon.Name2.Text).toBe("Cookie Saddle")
				expect(soon.Status2.Text).toBe("Back next week")
				expect(soon.Name3.Text).toBe("Bubbles Trail")
				expect(soon.Status3.Text).toBe("Back in 2 weeks")
				S.clean(c, expect)
				-- les 5 suivants déjà gagnés : la prochaine pas encore gagnée revient dans 6 semaines ; celle
				-- de la période déjà gagnée : « Possédé » (le palier 12 ne redonne rien)
				local c2 = v2client({
					lang = "fr",
					edit = function(p)
						p.weeklyTrack.won = { 31 + 128 }
						p.weeklyTrack.challenges = {}
					end,
				})
				openTab(c2, "track")
				local soon2 = body(c2).Page_track.Soon
				expect(flat(soon2.Name1)).toBe("Coussins « Nuage rose »")
				expect(soon2.Status1.Text).toBe("Possédé")
				expect(flat(soon2.Name2)).toBe("Titre « Copain fidèle »")
				expect(soon2.Status2.Text).toBe("Revient dans 6 semaines")
				expect(soon2.Status3.Text).toBe("Revient dans 7 semaines")
				-- aucun Défi tiré : le bloc est caché
				expect(body(c2).Page_track.ChallengesTitle.Visible).toBe(false)
				expect(body(c2).Page_track.Challenge1.Visible).toBe(false)
				S.clean(c2, expect)
			end
		)

		it(
			"première période : jusqu'au 2e lundi ; 24 / 24 tout réclamé : 12 coches, aucun prochain palier",
			function()
				local c = v2client({
					edit = function(p)
						p.weeklyTrack.period = 0
						p.weeklyTrack.firstPeriodEnd = 0
						p.weeklyTrack.points = 0
						p.weeklyTrack.claimed = { 0 }
					end,
				})
				openTab(c, "track")
				expect(body(c).Page_track.Ends.Text).toBe("Ends in 10 d")
				expect(body(c).Page_track.Points.Text).toBe("0 / 24 points")
				local c2 = v2client({
					edit = function(p)
						p.weeklyTrack.points = 30
						p.weeklyTrack.claimed = { 4095 }
					end,
				})
				openTab(c2, "track")
				local page = body(c2).Page_track
				expect(page.Points.Text).toBe("24 / 24 points")
				for i = 1, 12 do
					expect(page["Tier" .. i].Check:GetAttribute("Icon")).toBe("check")
				end
				-- palier 12 réclamé : le cosmétique de la période est à lui (« Possédé »), même si le bit
				-- `won` n'est pas encore arrivé
				expect(page.Soon.Status1.Text).toBe("Owned")
				S.clean(c, expect)
				S.clean(c2, expect)
			end
		)

		it(
			"Carnet : progression vers le prochain seuil, 8 paliers et 2 objets de Déco perso dans l'ordre, réclamés cochés",
			function()
				local c = v2client()
				openTab(c, "carnet")
				local page = body(c).Page_carnet
				expect(page.Progress.Text).toBe("Upgrades bought: 600 / 750") -- prochaine récompense : l'Établi (Déco perso)
				expect(page.Cell1.Head.Text).toBe("50")
				expect(page.Cell1.Kind.Text).toBe("Title")
				expect(page.Cell1.Reward.Text).toBe("Builder")
				expect(page.Cell1.Check:GetAttribute("Icon")).toBe("check")
				expect(page.Cell5.Head.Text).toBe("750")
				expect(page.Cell5.Kind.Text).toBe(S.Localization.get("en", "deco.title"))
				expect(page.Cell5.Reward.Text).toBe("Big Plop's Workbench")
				expect(page.Cell5.Check:GetAttribute("Icon")).toBe("")
				expect(page.Cell7.Reward.Text).toBe("Hammer Tap")
				expect(page.Cell10.Head.Text).toBe("10,000")
				expect(page.Cell10.Reward.Text).toBe("Builder's Crown")
				expect(S.selected(c)).toBe(page.Cell1)
				S.clean(c, expect)
				-- 10 000 niveaux : tout atteint, « 10 000 / 10 000 » en français
				local c2 = v2client({
					lang = "fr",
					edit = function(p)
						p.stats.upgradesBought = 10000
						p.carnet = { 255 }
					end,
				})
				openTab(c2, "carnet")
				local page2 = body(c2).Page_carnet
				expect(page2.Progress.Text).toBe("Améliorations achetées : 10 000 / 10 000")
				for i = 1, 10 do
					expect(page2["Cell" .. i].Check:GetAttribute("Icon")).toBe("check")
				end
				S.clean(c2, expect)
			end
		)

		it("WeeklyTrack ouvert seul : l'onglet de la piste, pas celui du Carnet", function()
			local c = v2client({ flags = { WeeklyTrack = true } })
			openTab(c, "carnet")
			expect(c.Obj.tabs()).toEqual({ "today", "track", "plop" })
			expect(c.Obj.currentTab() == "carnet").toBe(false)
			expect(body(c):FindFirstChild("Page_carnet")).toBeNil()
			expect(tabButtons(c)).toEqual({ "Tab_plop", "Tab_today", "Tab_track" })
			S.clean(c, expect)
		end)

		it(
			"valeurs hostiles du profil (piste, Défis, Carnet, niveaux) : valeurs sûres, aucune trace",
			function()
				local c = v2client({
					edit = function(p)
						p.weeklyTrack =
							{ points = 0 / 0, period = "x", claimed = "y", challenges = { "z", { id = 99 } } }
						p.carnet = "x"
						p.stats = { upgradesBought = -math.huge }
					end,
				})
				for _, tab in { "track", "carnet", "today" } do
					openTab(c, tab)
				end
				openTab(c, "track")
				expect(body(c).Page_track.Points.Text).toBe("0 / 24 points")
				expect(body(c).Page_track.ChallengesTitle.Visible).toBe(false)
				openTab(c, "carnet")
				expect(body(c).Page_carnet.Progress.Text).toBe("Upgrades bought: 0 / 50")
				S.clean(c, expect)
			end
		)

		it(
			"interrupteurs coupés (ou profil v1) : barre et pages de la v1.3, rien de la v2.0 construit ni envoyé ; coupés en direct : onglets cachés à l'ouverture suivante",
			function()
				for _, case in
					{ { flags = false }, {
						edit = function(p)
							p.version = 1
						end,
					} }
				do
					local c = v2client(case)
					openTab(c, "track")
					expect(c.Obj.tabs()).toEqual({ "today", "plop" })
					expect(c.Obj.currentTab()).toBe("today")
					expect(body(c):FindFirstChild("Page_track")).toBeNil()
					expect(body(c):FindFirstChild("Page_carnet")).toBeNil()
					local all = {}
					for _, b in body(c).Tabs.Strip:GetChildren() do
						if b:IsA("TextButton") then
							table.insert(all, b.Name)
						end
					end
					table.sort(all)
					expect(all).toEqual({ "Tab_onboarding", "Tab_plop", "Tab_today" })
					S.noV2Intent(c, expect)
					S.clean(c, expect)
				end
				-- ouvert en v2.0 puis coupé en direct : à l'ouverture suivante, plus d'onglet de la v2.0
				local c = v2client()
				openTab(c, "track")
				expect(c.Obj.currentTab()).toBe("track")
				S.event(c, nil)
				openTab(c, "track")
				expect(c.Obj.tabs()).toEqual({ "today", "plop" })
				expect(c.Obj.currentTab()).toBe("today")
				expect(tabButtons(c)).toEqual({ "Tab_plop", "Tab_today" })
				S.clean(c, expect)
			end
		)
	end)
end
