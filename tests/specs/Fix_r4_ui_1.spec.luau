--!nocheck
-- QA round 4 — fixer r4-ui-1, panneau Améliorer (src/client/UI/Panels/Upgrades.luau) :
--   * quêtes d'accueil d'achat (Q2 « Conga ×2 », Q5 « Achète Foulée ») : la carte de quête suit la
--     progression du SERVEUR (onboarding.p = achats faits pendant la quête, QuestService
--     onUpgradeBought « add » 1, remis à 0 à chaque quête), jamais le niveau total de la piste ;
--   * double appui sur « Acheter » : un seul BuyUpgrade, pas de toast d'erreur juste après un achat
--     réussi ; le Glow d'un achat en route n'est pas dépensé deux fois.
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

	local function pulsingScales(c)
		local out = {}
		for _, track in { "conga", "stride", "lure", "perches", "guard" } do
			if c.U._cards[track].pulse.Scale ~= 1 then
				table.insert(out, track)
			end
		end
		return out
	end

	-- toasts affichés (pile de UI/Toast)
	local function toasts(c)
		local gui = c.h.localPlayer.PlayerGui:FindFirstChild("Toasts")
		local stack = if gui then gui.Safe:FindFirstChild("Stack") else nil
		local n = 0
		if stack then
			for _, child in stack:GetChildren() do
				if child:IsA("GuiObject") then
					n += 1
				end
			end
		end
		return n
	end

	local function cost(c, track, level)
		return c.Formulas.upgradeCost(track, level)
	end

	-- ==========================================================================================
	describe("Fix r4-ui-1 › quêtes d'achat : progression du serveur, pas le niveau total", function()
		it(
			"Q2 après le premier achat de la quête (Conga 2, p = 1) : la carte Conga reste celle de la quête",
			function()
				-- Conga 1 acheté pendant Q1, Conga 2 pendant Q2 (p = 1) : il faut encore Conga 3
				local glow = 130
				local c = setup({ glow = glow, upgrades = ups(2), onboarding = { step = 2, p = 1 } })
				-- prémisses : Conga 3 est payable, Attrait (moins cher) aussi
				expect(cost(c, "conga", 2) <= glow).toBe(true)
				expect(cost(c, "lure", 0) < cost(c, "conga", 2)).toBe(true)
				c.PC.open("Upgrades")
				frames(c, 4)
				expect(c.U._quest()).toBe("conga")
				expect(c.U._pulsing()).toBe("conga")
				expect(markedTracks(c)).toEqual({ "conga" })
				expect(pulsingScales(c)).toEqual({ "conga" })
				expect(c.U.defaultSelection()).toBe(c.U._cards.conga.buy)
			end
		)

		it(
			"Q5 avec Foulée 1 déjà acheté en Q3/Q4 (p = 0) : la carte Foulée reste celle de la quête",
			function()
				local c = setup({ glow = 250, upgrades = ups(3, 1), onboarding = { step = 5, p = 0 } })
				expect(cost(c, "stride", 1) <= 250).toBe(true)
				c.PC.open("Upgrades")
				frames(c, 4)
				expect(c.U._quest()).toBe("stride")
				expect(c.U._pulsing()).toBe("stride")
				expect(markedTracks(c)).toEqual({ "stride" })
				-- aucune autre carte ne pulse (Attrait, moins chère, dépenserait le Glow de la quête)
				expect(pulsingScales(c)).toEqual({ "stride" })
			end
		)

		it("progression atteinte mais étape pas encore passée (p = n) : plus de carte de quête", function()
			local c = setup({ glow = 300, upgrades = ups(3), onboarding = { step = 2, p = 2 } })
			c.PC.open("Upgrades")
			frames(c, 2)
			expect(c.U._quest()).toBeNil()
			expect(c.U._pulsing()).toBe("lure")
		end)

		it("parcours réel de Q2 : niveaux 2 puis 3, la quête se termine au second achat", function()
			local c = setup({ glow = 400, upgrades = ups(1), onboarding = { step = 2, p = 0 } })
			c.PC.open("Upgrades")
			frames(c, 2)
			expect(c.U._quest()).toBe("conga")
			-- 1er achat de la quête (77 Glow) : Conga 2, p = 1
			patch(
				c,
				{ glow = 400 - cost(c, "conga", 1), upgrades = ups(2), onboarding = { step = 2, p = 1 } }
			)
			frames(c, 2)
			expect(c.U._quest()).toBe("conga")
			expect(c.U._pulsing()).toBe("conga")
			-- 2e achat : Conga 3, Q2 terminée → Q3 (parade de 6, pas une quête d'achat)
			patch(c, {
				glow = 400 - cost(c, "conga", 1) - cost(c, "conga", 2),
				upgrades = ups(3),
				onboarding = { step = 3, p = 0 },
			})
			frames(c, 2)
			expect(c.U._quest()).toBeNil()
		end)

		it("progression invalide (NaN, ∞, texte, table) : traitée comme 0, aucune erreur", function()
			local c = setup({ glow = 200, upgrades = ups(2), onboarding = { step = 2, p = 1 } })
			c.PC.open("Upgrades")
			for _, bad in { 0 / 0, math.huge, -math.huge, "1", {}, -3 } do
				patch(c, { onboarding = { step = 2, p = bad } })
				frames(c, 6)
				expect(c.U._quest()).toBe("conga")
			end
			expect(#c.h.errors).toBe(0)
		end)
	end)

	-- ==========================================================================================
	describe("Fix r4-ui-1 › double appui sur Acheter", function()
		it(
			"premier achat (carte unique, 69 Glow) : deux appuis → un seul BuyUpgrade, aucun toast",
			function()
				local c = setup({ glow = 69, upgrades = ups(0), onboarding = { step = 1, p = 0 } })
				c.PC.open("Upgrades", { focus = "conga" })
				frames(c, 2)
				local buy = c.U._cards.conga.buy
				buy.Activated:Fire()
				buy.Activated:Fire()
				c.h:settle(1)
				expect(#sent(c, "BuyUpgrade")).toBe(1)
				expect(toasts(c)).toBe(0)
				-- encore un appui avant la confirmation (quelques images plus tard) : toujours rien
				frames(c, 3)
				buy.Activated:Fire()
				c.h:settle(1)
				expect(#sent(c, "BuyUpgrade")).toBe(1)
				expect(toasts(c)).toBe(0)
				-- confirmation du serveur : niveau 1, 19 Glow ; l'achat en route est oublié
				patch(c, { glow = 69 - cost(c, "conga", 0), upgrades = ups(1) })
				expect(c.U._pending().conga).toBeNil()
			end
		)

		it("après la confirmation, un nouvel achat de la même carte part normalement", function()
			local c = setup({ glow = 200, upgrades = ups(1), onboarding = { step = 8, p = 0 } })
			c.PC.open("Upgrades")
			frames(c, 2)
			local buy = c.U._cards.conga.buy
			buy.Activated:Fire()
			c.h:settle(1)
			expect(#sent(c, "BuyUpgrade")).toBe(1)
			patch(c, { glow = 200 - cost(c, "conga", 1), upgrades = ups(2) })
			frames(c, 2)
			-- 123 Glow ≥ 120 (Conga 3) : second achat légitime, envoyé
			expect(200 - cost(c, "conga", 1) >= cost(c, "conga", 2)).toBe(true)
			buy.Activated:Fire()
			c.h:settle(1)
			expect(#sent(c, "BuyUpgrade")).toBe(2)
		end)

		it("pas de confirmation (refus, limite de débit) : l'achat redevient possible après 1 s", function()
			local c = setup({ glow = 200, upgrades = ups(1), onboarding = { step = 8, p = 0 } })
			c.PC.open("Upgrades")
			frames(c, 2)
			local buy = c.U._cards.conga.buy
			buy.Activated:Fire()
			c.h:settle(1)
			frames(c, 10) -- 0,5 s
			buy.Activated:Fire()
			c.h:settle(1)
			expect(#sent(c, "BuyUpgrade")).toBe(1)
			frames(c, 12) -- 1,1 s au total
			buy.Activated:Fire()
			c.h:settle(1)
			expect(#sent(c, "BuyUpgrade")).toBe(2)
		end)

		it("deux cartes d'affilée : le Glow de l'achat en route n'est pas dépensé deux fois", function()
			-- 140 Glow : Conga 2 (77) puis Attrait 1 (70) → 63 restants < 70 : refus local, pas d'envoi
			local c = setup({ glow = 140, upgrades = ups(1), onboarding = { step = 8, p = 0 } })
			c.PC.open("Upgrades")
			frames(c, 2)
			c.U._cards.conga.buy.Activated:Fire()
			c.h:settle(1)
			c.U._cards.lure.buy.Activated:Fire()
			c.h:settle(1)
			local out = sent(c, "BuyUpgrade")
			expect(#out).toBe(1)
			expect(out[1][1]).toBe("conga")
			-- l'affichage suit : Attrait n'est plus présenté comme payable, ni comme la carte qui pulse
			frames(c, 6)
			expect(c.U._cards.lure.buy:GetAttribute("Disabled")).toBe(true)
			expect(c.U._pulsing() ~= "lure").toBe(true)
			-- 150 Glow : les deux achats tiennent, les deux partent
			local c2 = setup({ glow = 150, upgrades = ups(1), onboarding = { step = 8, p = 0 } })
			c2.PC.open("Upgrades")
			frames(c2, 2)
			c2.U._cards.conga.buy.Activated:Fire()
			c2.U._cards.lure.buy.Activated:Fire()
			c2.h:settle(1)
			expect(#sent(c2, "BuyUpgrade")).toBe(2)
			expect(#c.h.errors + #c2.h.errors).toBe(0)
		end)
	end)
end
