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
				expect(plop.Cell5.Status.Text).toBe("✓") -- jour 7 atteint
				expect(plop.Cell6.Status.Text).toBe("") -- jour 10
				-- un nouveau : l'onglet Accueil existe et montre les étapes faites
				local c2 = setup({ onboarding = { step = 3, done = false, demoDone = false } })
				c2.PC.open("Objectives", "onboarding")
				expect(c2.Obj.currentTab()).toBe("onboarding")
				local steps = c2.PC.window("Objectives").Body.Page_onboarding
				expect(steps.Cell3.Status.Text).toBe("✓")
				expect(steps.Cell4.Status.Text).toBe("")
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
end
