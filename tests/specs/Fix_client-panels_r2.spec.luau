--!nocheck
-- QA round 2 — paquet client-panels : pendant les quêtes d'accueil d'achat (Q2 « Conga ×2 »,
-- Q5 « Achète Foulée », Q7 « 10 perchoirs »), le panneau Améliorer doit désigner la carte de la
-- quête (contour doré + pulsation quand elle est achetable) et jamais une autre carte (Attrait, la
-- moins chère) qui ferait dépenser le Glow prévu pour la quête (GDD §3). Hors accueil, la règle
-- « la carte achetable la moins chère pulse » (§10.3) ne change pas.
local task = require("@lune/task")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000
	local TODAY = math.floor(T0 / 86400)

	local function ups(conga, stride, lure, perches, guard)
		return {
			conga = conga or 0,
			stride = stride or 0,
			lure = lure or 0,
			perches = perches or 0,
			guard = guard or 0,
		}
	end

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
			upgrades = ups(),
			boosts = { personalUntil = 0 },
			caps = { day = 0, snipDust = 0, wispDust = 0, cheers = 0, duo = false },
			nebbies = {},
			nextUid = 1,
			perchIncome = 0,
			atlas = { 0, 0, 0, 0, 0, 0, 0 },
			badges = { 0, 0, 0, 0 },
			atlasRewards = 0,
			onboarding = { step = 8, p = 0 },
			daily = { day = TODAY, step = 2 },
			quests = { day = 0, list = {}, rerolls = 0, starClaimed = false },
			weekly = { week = 0, banked = 0, claimed = false },
			rookie = { sessions = 1, playSeconds = 60, done = false },
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
			stats = { parades = 3 },
			passes = {},
		}
		for k, v in over or {} do
			p[k] = v
		end
		return p
	end

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
			PC = h:require(CLIENT .. "Controllers.PanelController"),
			Theme = h:require(CLIENT .. "UI.Theme"),
			Formulas = h:require("ReplicatedStorage.Shared.Logic.Formulas"),
			Model = h:require(CLIENT .. "UI.Panels.Model"),
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
		c.U = h:require(CLIENT .. "UI.Panels.Upgrades")
		return c
	end

	local function frames(c, n, dt)
		for _ = 1, n do
			c.Clock.advance(dt or 0.05)
			c.h:step(dt or 0.05, 1)
		end
	end

	local function patch(c, values)
		c.h:fireClient(REMOTES .. "DataPatch", values, {})
		frames(c, 1)
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

	-- Carte au contour doré (Widgets.highlight : UIStroke « Stroke » épaisseur 3, couleur Gold)
	local function marked(c, track)
		local stroke = c.U._cards[track].visual:FindFirstChild("Stroke")
		return stroke ~= nil and stroke.Thickness == 3 and stroke.Color == c.Theme.Colors.Gold
	end

	local function markedTracks(c)
		local out = {}
		for _, track in { "conga", "stride", "lure", "perches", "guard" } do
			if marked(c, track) then
				table.insert(out, track)
			end
		end
		return out
	end

	local function cost(c, track, level)
		return c.Formulas.upgradeCost(track, level)
	end

	-- ==========================================================================================
	describe("Fix client-panels r2 › Améliorer pendant les quêtes d'accueil", function()
		it("Q2 « Conga ×2 » (Conga 1, 100 Glow) : Conga pulse, pas Attrait (la moins chère)", function()
			local c = setup({ glow = 100, upgrades = ups(1), onboarding = { step = 2, p = 1 } })
			-- prémisse du défaut : Attrait (70) est moins cher que Conga niveau 1 (77)
			expect(cost(c, "lure", 0) < cost(c, "conga", 1)).toBe(true)
			expect(c.Model.cheapestAffordable(c.Model.view(c.State.get), T0)).toBe("lure")
			c.PC.open("Upgrades")
			frames(c, 2)
			expect(c.U._pulsing()).toBe("conga")
			expect(c.U._quest()).toBe("conga")
			expect(markedTracks(c)).toEqual({ "conga" })
			-- toutes les cartes restent visibles (ce n'est pas la carte unique du premier achat)
			expect(c.U._focus()).toBeNil()
			expect(c.U._cards.lure.holder.Visible).toBe(true)
			-- manette : la sélection par défaut est le bouton de la carte de quête
			expect(c.U.defaultSelection()).toBe(c.U._cards.conga.buy)
			-- la carte pulse vraiment (UIScale), Attrait reste immobile
			frames(c, 4)
			expect(c.U._cards.conga.pulse.Scale > 1).toBe(true)
			expect(c.U._cards.lure.pulse.Scale).toBe(1)
		end)

		it("Q5 « Achète Foulée » (Conga 3, 250 Glow) : Foulée pulse", function()
			local c = setup({ glow = 250, upgrades = ups(3), onboarding = { step = 5, p = 0 } })
			c.PC.open("Upgrades")
			frames(c, 2)
			expect(c.U._pulsing()).toBe("stride")
			expect(markedTracks(c)).toEqual({ "stride" })
			expect(c.U.defaultSelection()).toBe(c.U._cards.stride.buy)
		end)

		it("Q7 « 10 perchoirs » (400 Glow) : Perchoirs pulse", function()
			local c = setup({ glow = 400, upgrades = ups(3, 1), onboarding = { step = 7, p = 3 } })
			c.PC.open("Upgrades")
			frames(c, 2)
			expect(c.U._pulsing()).toBe("perches")
			expect(markedTracks(c)).toEqual({ "perches" })
		end)

		it("carte de quête pas encore payable : contour doré, AUCUNE autre carte ne pulse", function()
			-- 75 Glow : Foulée (80) hors de portée, Attrait (70) payable
			local c = setup({ glow = 75, upgrades = ups(3), onboarding = { step = 5, p = 0 } })
			c.PC.open("Upgrades")
			frames(c, 4)
			expect(c.U._pulsing()).toBeNil()
			expect(markedTracks(c)).toEqual({ "stride" })
			expect(c.U._cards.lure.pulse.Scale).toBe(1)
			expect(c.U.defaultSelection()).toBe(c.U._cards.stride.buy)
			-- le Glow arrive : la carte de quête se met à pulser
			patch(c, { glow = 90 })
			frames(c, 2)
			expect(c.U._pulsing()).toBe("stride")
		end)

		it("acheter la carte de quête envoie BuyUpgrade(stride)", function()
			local c = setup({ glow = 250, upgrades = ups(3), onboarding = { step = 5, p = 0 } })
			c.PC.open("Upgrades")
			c.U._cards.stride.buy.Activated:Fire()
			local out = sent(c, "BuyUpgrade")
			expect(#out).toBe(1)
			expect(out[1][1]).toBe("stride")
		end)

		it("la quête avance pendant que le panneau est ouvert : retour à la moins chère", function()
			local c = setup({ glow = 300, upgrades = ups(1), onboarding = { step = 2, p = 1 } })
			c.PC.open("Upgrades")
			frames(c, 2)
			expect(c.U._pulsing()).toBe("conga")
			-- achat confirmé : Conga 2, Q2 finie → Q3 « Parade de 6 » (pas une quête d'achat)
			patch(c, { glow = 223, upgrades = ups(2), onboarding = { step = 3, p = 0 } })
			frames(c, 2)
			expect(c.U._quest()).toBeNil()
			expect(c.U._pulsing()).toBe("lure")
			expect(markedTracks(c)).toEqual({})
		end)

		it("objectif déjà atteint (réplication en deux temps) : plus de carte de quête", function()
			-- Conga 2 répliqué avant le passage à Q3
			local c = setup({ glow = 300, upgrades = ups(2), onboarding = { step = 2, p = 1 } })
			c.PC.open("Upgrades")
			frames(c, 2)
			expect(c.U._quest()).toBeNil()
			expect(c.U._pulsing()).toBe("lure")
			-- Q7 : déjà 10 perchoirs (pass Extra Perches + niveau 1)
			local c2 = setup({
				glow = 400,
				upgrades = ups(3, 1, 0, 1),
				onboarding = { step = 7, p = 0 },
				passes = { ExtraPerches = true },
			})
			c2.PC.open("Upgrades")
			frames(c2, 2)
			expect(c2.U._quest()).toBeNil()
		end)

		it("accueil fini (step 8) : règle normale, la moins chère pulse", function()
			local c = setup({ glow = 100, upgrades = ups(1), onboarding = { step = 8, p = 0 } })
			c.PC.open("Upgrades")
			frames(c, 2)
			expect(c.U._quest()).toBeNil()
			expect(c.U._pulsing()).toBe("lure")
			expect(markedTracks(c)).toEqual({})
		end)

		it("quêtes sans achat (Q1, Q3, Q4, Q6) : règle normale", function()
			for _, step in { 1, 3, 4, 6 } do
				local c = setup({ glow = 100, upgrades = ups(1), onboarding = { step = step, p = 0 } })
				c.PC.open("Upgrades")
				frames(c, 2)
				expect(c.U._quest()).toBeNil()
				expect(c.U._pulsing()).toBe("lure")
			end
		end)

		it("piste de quête au plafond : règle normale", function()
			local c = setup({ glow = 10 ^ 6, upgrades = ups(3, 20), onboarding = { step = 5, p = 0 } })
			c.PC.open("Upgrades")
			frames(c, 2)
			expect(c.U._quest()).toBeNil()
			expect(c.U._pulsing()).toBe("lure")
		end)

		it('premier achat : { focus = "conga" } garde la priorité (carte unique)', function()
			local c = setup({ glow = 60, upgrades = ups(0), onboarding = { step = 1, p = 0 } })
			c.PC.open("Upgrades", { focus = "conga" })
			frames(c, 2)
			expect(c.U._focus()).toBe("conga")
			expect(c.U._pulsing()).toBe("conga")
			expect(c.U._cards.lure.holder.Visible).toBe(false)
		end)

		it(
			"profil d'accueil invalide (NaN, ∞, négatif, texte, table) : aucune erreur, règle normale",
			function()
				local c = setup({ glow = 100, upgrades = ups(1), onboarding = { step = 8, p = 0 } })
				c.PC.open("Upgrades")
				for _, bad in
					{
						{ step = 0 / 0 },
						{ step = math.huge },
						{ step = -math.huge },
						{ step = -2 },
						{ step = "2" },
						{ step = {} },
						"q2",
						42,
						false,
					}
				do
					patch(c, { onboarding = bad })
					frames(c, 6)
					expect(c.U._quest()).toBeNil()
					expect(c.U._pulsing()).toBe("lure")
				end
				-- étape fractionnaire : arrondie comme le reste du client (2,7 → Q2)
				patch(c, { onboarding = { step = 2.7 } })
				frames(c, 6)
				expect(c.U._pulsing()).toBe("conga")
			end
		)

		it(
			"Mouvement réduit : contour fixe sur la carte de quête, conservé quand elle n'est plus payable",
			function()
				local c = setup({
					glow = 250,
					upgrades = ups(3),
					onboarding = { step = 5, p = 0 },
					settings = { reducedMotion = true, lang = "en" },
				})
				c.PC.open("Upgrades")
				frames(c, 4)
				expect(c.U._pulsing()).toBe("stride")
				expect(c.U._cards.stride.pulse.Scale).toBe(1) -- pas de pulsation
				expect(markedTracks(c)).toEqual({ "stride" })
				-- plus assez de Glow : plus de pulsation, mais le contour de quête reste
				patch(c, { glow = 75 })
				frames(c, 8)
				expect(c.U._pulsing()).toBeNil()
				expect(markedTracks(c)).toEqual({ "stride" })
				-- quête suivante (Q6) : contour transféré à la moins chère, retiré de Foulée
				patch(c, { glow = 250, onboarding = { step = 6, p = 0 } })
				frames(c, 8)
				expect(c.U._pulsing()).toBe("lure")
				expect(markedTracks(c)).toEqual({ "lure" })
			end
		)

		it("fermer / rouvrir et changer de langue : la carte de quête est recalculée", function()
			local c = setup({ glow = 250, upgrades = ups(3), onboarding = { step = 5, p = 0 } })
			c.PC.open("Upgrades")
			frames(c, 2)
			expect(c.U._pulsing()).toBe("stride")
			c.PC.close()
			task.wait(0.3)
			-- la progression change panneau fermé
			patch(c, { upgrades = ups(3, 1), onboarding = { step = 6, p = 0 } })
			c.PC.open("Upgrades")
			frames(c, 2)
			expect(c.U._quest()).toBeNil()
			expect(c.U._pulsing()).toBe("lure")
			patch(c, { onboarding = { step = 7, p = 0 } })
			c.Prefs._onSettings({ lang = "fr" })
			frames(c, 2)
			expect(c.U._pulsing()).toBe("perches")
			expect(markedTracks(c)).toEqual({ "perches" })
		end)
	end)
end
