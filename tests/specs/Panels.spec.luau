--!nocheck
-- Panneaux (paquet client-panels) : Améliorer (prix, Glow prédit, refus, MAX, accueil à une carte),
-- Supernova (aperçu, maintien 1 s, port sûr), Collection (perchoirs, réserve virtualisée, sélection
-- et libération confirmée, verrou, Forge, Atlas, Guide), Objectifs (quêtes, relance, calendrier,
-- Grand Défilé, accueil), Boutique (id 0, prix réels, possédé, « ≈ », Glow Party, Starter Kit,
-- codes), Équipage (invitations limitées, quitter, carte ✓ / ✕), Réglages (générés, optimistes,
-- Zen au port sûr + recharge, langue, cosmétiques possédés, LiveOps Admin), écran de retour, et
-- calculs purs de Panels/Model. Chaque intention envoyée est vérifiée ; les entrées malveillantes
-- n'envoient rien.
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Vector3 = roblox.Vector3
local Vector2 = roblox.Vector2
local CFrame = roblox.CFrame
local Enum = roblox.Enum

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000
	local TODAY = math.floor(T0 / 86400)

	local function neb(s, f, v, st, lk)
		return { s = s, f = f or 0, v = v or 0, st = st or 1, lk = lk }
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
			daily = { day = TODAY, step = 2 },
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

	local function setup(over, before)
		local h = Harness.new({ mode = "client" })
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
			Monetization = h:require("ReplicatedStorage.Shared.Config.Monetization"),
			Formulas = h:require("ReplicatedStorage.Shared.Logic.Formulas"),
			Model = h:require(CLIENT .. "UI.Panels.Model"),
		}
		if before then
			before(c)
		end
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

	local function panel(c, name)
		return c.h:require(CLIENT .. "UI.Panels." .. name)
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

	local function click(button)
		button.Activated:Fire()
	end

	local function toasts(c)
		local out = {}
		local screen = c.h.localPlayer.PlayerGui:FindFirstChild("Toasts")
		if not screen then
			return out
		end
		for _, t in screen.Safe.Stack:GetChildren() do
			if t.Name == "Toast" then
				table.insert(out, t.Label.Text)
			end
		end
		return out
	end

	local function goHome(c, slot)
		local me = c.h.localPlayer
		me:SetAttribute("Slot", slot or 1)
		local gate = c.WorldLayout.gateCFrame(slot or 1).Position
		me.Character.HumanoidRootPart.CFrame = CFrame.new(gate.X, 3, gate.Z)
	end

	local function goAway(c)
		local me = c.h.localPlayer
		me:SetAttribute("Slot", 1)
		me.Character.HumanoidRootPart.CFrame = CFrame.new(0, 3, 30)
	end

	-- ==========================================================================================
	describe("Panels › Améliorer", function()
		it("5 cartes : niveau, effet actuel → suivant, prix ; Acheter envoie BuyUpgrade(track)", function()
			local c = setup({ glow = 60 })
			c.PC.open("Upgrades")
			local U = panel(c, "Upgrades")
			local conga = U._cards.conga
			expect(conga.buyLabel.Text).toBe("50")
			expect(conga.effect.Text).toBe("3 → 4 slots")
			expect(conga.level.Text).toBe("Lv. 0")
			expect(conga.name.Text).toBe("Conga")
			expect(U._cards.stride.effect.Text).toBe("16 → 16.5 speed")
			expect(conga.buy.Size.Y.Offset).toBe(96)
			click(conga.buy)
			expect(#sent(c, "BuyUpgrade")).toBe(1)
			expect(sent(c, "BuyUpgrade")[1][1]).toBe("conga")
		end)

		it(
			"refus local si le Glow prédit ne suffit pas : secousse, toast « Il manque », rien d'envoyé",
			function()
				local c = setup({ glow = 60 })
				c.PC.open("Upgrades")
				local U = panel(c, "Upgrades")
				click(U._cards.stride.buy) -- 80 > 60
				expect(#sent(c, "BuyUpgrade")).toBe(0)
				expect(table.find(toasts(c), "20 Glow missing") ~= nil).toBe(true)
			end
		)

		it("le Glow prédit (revenu passif) rend l'achat possible sans attendre le serveur", function()
			local c = setup({ glow = 0, idleRate = 10, lastSettle = T0 })
			c.PC.open("Upgrades")
			local U = panel(c, "Upgrades")
			click(U._cards.conga.buy)
			expect(#sent(c, "BuyUpgrade")).toBe(0)
			frames(c, 120) -- 6 s → 60 Glow prédits
			click(U._cards.conga.buy)
			expect(#sent(c, "BuyUpgrade")).toBe(1)
			expect(U._pulsing()).toBe("conga")
		end)

		it("MAX au plafond : bouton MAX, aucun envoi", function()
			local c = setup({
				glow = 10 ^ 9,
				upgrades = { conga = 0, stride = 20, lure = 0, perches = 0, guard = 5 },
			})
			c.PC.open("Upgrades")
			local U = panel(c, "Upgrades")
			expect(U._cards.guard.buyLabel.Text).toBe("MAX")
			expect(U._cards.stride.buyLabel.Text).toBe("MAX")
			click(U._cards.guard.buy)
			click(U._cards.stride.buy)
			expect(#sent(c, "BuyUpgrade")).toBe(0)
		end)

		it("la confirmation serveur fait défiler le niveau et l'effet suivant", function()
			local c = setup({ glow = 100 })
			c.PC.open("Upgrades")
			local U = panel(c, "Upgrades")
			patch(c, { glow = 50, upgrades = { conga = 1, stride = 0, lure = 0, perches = 0, guard = 0 } })
			task.wait(0.4) -- le niveau défile en 0,3 s
			frames(c, 3)
			expect(U._cards.conga.level.Text).toBe("Lv. 1")
			expect(U._cards.conga.effect.Text).toBe("4 → 5 slots")
			expect(U._cards.conga.buyLabel.Text).toBe("77")
		end)

		it("Perchoirs : effet avec jalons d'Atlas et pass Extra Perches", function()
			local c = setup({ glow = 0, passes = { ExtraPerches = true } })
			c.PC.open("Upgrades")
			expect(panel(c, "Upgrades")._cards.perches.effect.Text).toBe("9 → 10 perches")
		end)

		it("accueil : une seule carte en surbrillance, fermeture 0,6 s après l'achat", function()
			local c = setup({ glow = 50, onboarding = { step = 1, p = 0 } })
			c.PC.open("Upgrades", { focus = "conga" })
			local U = panel(c, "Upgrades")
			expect(U._focus()).toBe("conga")
			expect(U._cards.conga.holder.Visible).toBe(true)
			expect(U._cards.stride.holder.Visible).toBe(false)
			expect(c.PC.page("Upgrades").Body.SupernovaButton.Visible).toBe(false)
			click(U._cards.conga.buy)
			expect(#sent(c, "BuyUpgrade")).toBe(1)
			patch(c, { glow = 0, upgrades = { conga = 1, stride = 0, lure = 0, perches = 0, guard = 0 } })
			expect(c.PC.current()).toBe("Upgrades")
			task.wait(0.7)
			expect(c.PC.current()).toBeNil()
			-- réouverture normale : toutes les cartes
			c.PC.open("Upgrades")
			expect(U._focus()).toBeNil()
			expect(U._cards.stride.holder.Visible).toBe(true)
		end)

		it("arguments d'accueil invalides : aucune focalisation", function()
			local c = setup({ glow = 50 })
			local U = panel(c, "Upgrades")
			for _, args in { { focus = "hack" }, { focus = 5 }, "x", 12, { focus = {} } } do
				c.PC.close()
				c.PC.open("Upgrades", args)
				expect(U._focus()).toBeNil()
			end
		end)

		it("bouton Supernova : anneau de progression et ouverture de l'aperçu", function()
			local c = setup({ glow = 200000 })
			c.PC.open("Upgrades")
			local button = c.PC.page("Upgrades").Body.SupernovaButton
			expect(button.Progress.Text).toBe("200K / 400K")
			click(button)
			expect(c.PC.current()).toBe("Supernova")
		end)

		it("hasAction : une amélioration est achetable", function()
			local c = setup({ glow = 10 })
			local U = panel(c, "Upgrades")
			expect(U.hasAction()).toBe(false)
			patch(c, { glow = 50 })
			expect(U.hasAction()).toBe(true)
		end)
	end)

	-- ==========================================================================================
	describe("Panels › Supernova", function()
		it("aperçu : Tu gardes / Remis à zéro, gains et coût (mêmes règles que le serveur)", function()
			local c = setup({ glow = 100000, supernovas = 2 })
			goHome(c)
			c.PC.open("Supernova")
			local S = panel(c, "Supernova")
			local refs = S._refs
			expect(refs.cost.Text).toBe("Cost: 40M Glow")
			expect(refs.gains[1].Text).toBe("+80% → +120% income")
			expect(refs.gains[2].Text).toBe("Conga cap 25 → 30")
			expect(refs.gains[3].Text).toBe("Dash cooldown 6.5s → 6.25s")
			expect(refs.gains[4].Text).toBe("New line aura: Silver")
			expect(refs.missing.Text).toBe("39.9M Glow to go")
			local resets = {}
			for _, child in refs.resetList:GetChildren() do
				if child:IsA("TextLabel") then
					table.insert(resets, child.Text)
				end
			end
			expect(table.find(resets, "↺ Glow") ~= nil).toBe(true)
			expect(table.find(resets, "↺ Conga levels") ~= nil).toBe(true)
			expect(#resets).toBe(4)
		end)

		it("maintien 1 s dans le port sûr : un seul envoi, puis fermeture", function()
			local c = setup({ glow = 400000 })
			goHome(c)
			c.PC.open("Supernova")
			local S = panel(c, "Supernova")
			local hold = S._refs.hold
			hold.MouseButton1Down:Fire()
			frames(c, 10) -- 0,5 s
			expect(#sent(c, "Supernova")).toBe(0)
			frames(c, 12) -- 1,1 s
			expect(#sent(c, "Supernova")).toBe(1)
			hold.MouseButton1Down:Fire()
			frames(c, 25)
			expect(#sent(c, "Supernova")).toBe(1)
			task.wait(0.35)
			expect(c.PC.current()).toBeNil()
		end)

		it("relâcher avant 1 s annule", function()
			local c = setup({ glow = 400000 })
			goHome(c)
			c.PC.open("Supernova")
			local hold = panel(c, "Supernova")._refs.hold
			hold.MouseButton1Down:Fire()
			frames(c, 15)
			hold.MouseButton1Up:Fire()
			frames(c, 30)
			expect(#sent(c, "Supernova")).toBe(0)
			expect(panel(c, "Supernova")._holding()).toBe(false)
		end)

		it(
			"hors du port sûr : « Rentre au Nid », refus ; quitter le port pendant le maintien annule",
			function()
				local c = setup({ glow = 400000 })
				goAway(c)
				c.PC.open("Supernova")
				local S = panel(c, "Supernova")
				expect(S._refs.status.Visible).toBe(true)
				expect(S._refs.status.Text).toBe("Go back to your Nest")
				S._refs.hold.MouseButton1Down:Fire()
				frames(c, 30)
				expect(#sent(c, "Supernova")).toBe(0)
				goHome(c)
				frames(c, 6)
				S._refs.hold.MouseButton1Down:Fire()
				frames(c, 6)
				goAway(c)
				frames(c, 30)
				expect(#sent(c, "Supernova")).toBe(0)
			end
		)

		it("Glow insuffisant ou personnage absent : aucun envoi", function()
			local c = setup({ glow = 1000 })
			goHome(c)
			c.PC.open("Supernova")
			local S = panel(c, "Supernova")
			S._refs.hold.MouseButton1Down:Fire()
			frames(c, 30)
			expect(#sent(c, "Supernova")).toBe(0)
			patch(c, { glow = 10 ^ 7 })
			c.h.localPlayer.Character:Destroy()
			c.h.localPlayer.Character = nil
			expect(S._inOwnHarbor()).toBe(false)
			S._refs.hold.MouseButton1Down:Fire()
			frames(c, 30)
			expect(#sent(c, "Supernova")).toBe(0)
		end)

		it("hasAction : Glow prédit ≥ coût", function()
			local c = setup({ glow = 399999 })
			local S = panel(c, "Supernova")
			expect(S.hasAction()).toBe(false)
			patch(c, { glow = 400000 })
			expect(S.hasAction()).toBe(true)
		end)
	end)

	-- ==========================================================================================
	describe("Panels › Collection", function()
		local function base()
			return {
				nebbies = {
					u1 = neb(1),
					u2 = neb(1),
					u3 = neb(1),
					u4 = neb(16),
					u5 = neb(36), -- Cosmique : jamais libérable
					u6 = neb(1, 0, 0, 1, true), -- verrouillé
				},
				idleRate = 10016,
				perchIncome = 10016,
				stardust = 100,
			}
		end

		-- case de la réserve liée à `uid` (fait défiler la grille virtualisée jusqu'à elle)
		local function cellFor(C, uid)
			local st = C._state()
			local index = table.find(st.sorted, uid)
			st.grid:scrollTo(index)
			for _, cell in st.grid:cells() do
				if cell:GetAttribute("Uid") == uid and cell.Visible then
					return cell
				end
			end
			return nil
		end

		it("Perchoirs : les N meilleurs revenus, places libres et revenu de chacun", function()
			local c = setup(base())
			c.PC.open("Collection", { tab = "perches" })
			local body = c.PC.page("Collection").Body.Tab_perches
			expect(body.Header.Text).toBe("Perches 3/3")
			local grid = body.Grid
			expect(grid.Perch1.Icon.Visible).toBe(true)
			expect(grid.Perch1.Income.Text).toBe("+10K/s")
			expect(grid.Perch2.Income.Text).toBe("+15/s")
		end)

		it("Réserve : tri revenu / rareté / récent", function()
			local c = setup(base())
			c.PC.open("Collection", { tab = "stash" })
			local C = panel(c, "Collection")
			expect(C._state().sorted).toEqual({ "u5", "u4", "u1", "u2", "u3", "u6" })
			C._setSort("recent")
			expect(C._state().sorted).toEqual({ "u6", "u5", "u4", "u3", "u2", "u1" })
			C._setSort("rarity")
			expect(C._state().sorted[1]).toBe("u5")
			local count = c.PC.page("Collection").Body.Tab_stash.Toolbar.Count
			expect(count.Text).toBe("6/300")
		end)

		it("Réserve virtualisée : 600 Nebbies, une poignée de cases réutilisées", function()
			local nebbies = {}
			for i = 1, 600 do
				nebbies["u" .. i] = neb((i % 7) + 1)
			end
			local c = setup({ nebbies = nebbies, passes = { StashPlus = true } })
			c.PC.open("Collection", { tab = "stash" })
			local C = panel(c, "Collection")
			local grid = C._state().grid
			expect(grid:count()).toBe(600)
			expect(#grid:cells() <= 20).toBe(true)
			local last = C._state().sorted[600]
			expect(cellFor(C, last) ~= nil).toBe(true)
			expect(#grid:cells() <= 20).toBe(true)
			expect(c.PC.page("Collection").Body.Tab_stash.Toolbar.Count.Text).toBe("600/600")
		end)

		it(
			"libération en lot : sélection, verrouillés et Cosmiques refusés, confirmation en deux appuis",
			function()
				local c = setup(base())
				c.PC.open("Collection", { tab = "stash" })
				local C = panel(c, "Collection")
				C._setSelectMode(true)
				C._tap(cellFor(C, "u1"))
				C._tap(cellFor(C, "u2"))
				C._tap(cellFor(C, "u5")) -- Cosmique
				C._tap(cellFor(C, "u6")) -- verrouillé
				expect(C._state().selectedCount).toBe(2)
				C._release()
				expect(#sent(c, "Release")).toBe(0)
				expect(C._state().armed).toBe(true)
				local label = c.PC.page("Collection").Body.Tab_stash.Actions.Release.Label
				expect(label.Text).toBe("Release 2 for 2 ✦?")
				C._release()
				expect(#sent(c, "Release")).toBe(1)
				expect(sent(c, "Release")[1][1]).toEqual({ "u1", "u2" })
				expect(C._state().selectMode).toBe(false)
			end
		)

		it("la confirmation expire après 4 s", function()
			local c = setup(base())
			c.PC.open("Collection", { tab = "stash" })
			local C = panel(c, "Collection")
			C._tap(cellFor(C, "u1"))
			C._release()
			frames(c, 100) -- 5 s
			expect(C._state().armed).toBe(false)
			C._release()
			expect(#sent(c, "Release")).toBe(0)
		end)

		it("sélection plafonnée à 50 (limite du remote)", function()
			local nebbies = {}
			for i = 1, 60 do
				nebbies["u" .. i] = neb(1)
			end
			local c = setup({ nebbies = nebbies })
			c.PC.open("Collection", { tab = "stash" })
			local C = panel(c, "Collection")
			C._setSelectMode(true)
			for _, uid in table.clone(C._state().sorted) do
				local cell = cellFor(C, uid)
				C._tap(cell)
			end
			expect(C._state().selectedCount).toBe(50)
		end)

		it("verrou : SetLock(uid, true) puis (uid, false)", function()
			local c = setup(base())
			c.PC.open("Collection", { tab = "stash" })
			local C = panel(c, "Collection")
			C._tap(cellFor(C, "u1"))
			expect(C._state().focusUid).toBe("u1")
			C._lock()
			C._tap(cellFor(C, "u6"))
			C._lock()
			local locks = sent(c, "SetLock")
			expect(locks[1][1]).toBe("u1")
			expect(locks[1][2]).toBe(true)
			expect(locks[2][1]).toBe("u6")
			expect(locks[2][2]).toBe(false)
		end)

		it("Forge : groupe de 3 identiques, Fuse(uid choisi), verrouillé gardé comme résultat", function()
			local nebbies = { u1 = neb(1), u2 = neb(1, 0, 0, 1, true), u3 = neb(1), u4 = neb(9) }
			local c = setup({ nebbies = nebbies, stardust = 25 })
			c.PC.open("Collection", { tab = "forge" })
			local C = panel(c, "Collection")
			local row = C._state().forgeRows[1]
			expect(row.frame.Visible).toBe(true)
			expect(row.cost.Text).toBe("25 ✦")
			click(row.fuse)
			expect(sent(c, "Fuse")[1][1]).toBe("u2")
			click(c.PC.page("Collection").Body.Tab_forge.FuseAll)
			expect(#sent(c, "FuseAll")).toBe(1)
			expect(C.hasAction()).toBe(true)
		end)

		it("Forge : Stardust insuffisante ou copies verrouillées → refus sans envoi", function()
			local c = setup({ nebbies = { u1 = neb(1), u2 = neb(1), u3 = neb(1) }, stardust = 10 })
			c.PC.open("Collection", { tab = "forge" })
			local C = panel(c, "Collection")
			click(C._state().forgeRows[1].fuse)
			expect(#sent(c, "Fuse")).toBe(0)
			expect(table.find(toasts(c), "15 Stardust missing") ~= nil).toBe(true)
			expect(C.hasAction()).toBe(false)
			patch(c, {
				stardust = 1000,
				nebbies = { u1 = neb(1, 0, 0, 1, true), u2 = neb(1, 0, 0, 1, true), u3 = neb(1) },
			})
			frames(c, 2)
			click(C._state().forgeRows[1].fuse)
			expect(#sent(c, "Fuse")).toBe(0)
			expect(C.hasAction()).toBe(false)
		end)

		it("animation Starforge : orbite, flash, résultat et étoiles, puis disparition", function()
			local c = setup(base())
			c.PC.open("Collection", { tab = "forge" })
			local C = panel(c, "Collection")
			c.ScreenFX.Celebrated:Fire({
				kind = "starforge",
				data = { uid = "u1", s = 1, f = 0, v = 0, stars = 3 },
			})
			c.h:settle(1)
			expect(C._state().anim ~= nil).toBe(true)
			local fx = c.PC.page("Collection").Body.ForgeFx
			expect(fx.Visible).toBe(true)
			frames(c, 40) -- 2 s
			expect(fx.Stars.Text).toBe("★★★")
			expect(fx.Stamp.Text).toBe("★3!")
			frames(c, 40)
			expect(C._state().anim).toBeNil()
			expect(fx.Visible).toBe(false)
			-- données malformées : ignorées
			c.ScreenFX.Celebrated:Fire({ kind = "starforge", data = { s = 999, stars = "x" } })
			c.h:settle(1)
			expect(C._state().anim).toBeNil()
		end)

		it("Atlas : verrouillé avant Q4, puis grille, progression et « NOUVEAU ! »", function()
			local c = setup({ onboarding = { step = 3, p = 0 } })
			c.PC.open("Collection", { tab = "atlas" })
			local tab = c.PC.page("Collection").Body.Tab_atlas
			expect(tab.Locked.Visible).toBe(true)
			expect(tab.List.Visible).toBe(false)
			patch(c, { onboarding = { step = 8, p = 0 }, atlas = { 1, 0, 0, 0, 0, 0, 0 } })
			frames(c, 2)
			expect(tab.Locked.Visible).toBe(false)
			expect(tab.Progress.Text).toBe("1/150")
			expect(tab.Next.Text).toBe("Next: 12 entries")
			local row = tab.List.Species1
			expect(row.Form0.Q.Visible).toBe(false)
			expect(row.Form1.Q.Visible).toBe(true)
			c.ScreenFX.Celebrated:Fire({
				kind = "atlasNew",
				data = { entries = { { s = 1, f = 0 }, "bad", { s = "x" } } },
			})
			c.h:settle(1)
			frames(c, 2)
			expect(row.Form0.New.Visible).toBe(true)
			c.PC.nextTab(1) -- quitte l'Atlas : les marques « nouveau » sont vues
			c.PC.nextTab(-1)
			expect(row.Form0.New.Visible).toBe(false)
		end)

		it("Guide : probabilités lues dans la configuration, dans la langue du joueur", function()
			local c = setup({})
			c.PC.open("Collection", { tab = "guide" })
			local list = c.PC.page("Collection").Body.Tab_guide.List
			local texts = {}
			for _, child in list:GetChildren() do
				if child:IsA("TextLabel") then
					table.insert(texts, child.Text)
				end
			end
			local all = table.concat(texts, "\n")
			expect(
				string.find(all, "Outer Meadow — Common: 78% · Uncommon: 19% · Rare: 3%", 1, true) ~= nil
			).toBe(true)
			expect(string.find(all, "Golden ×4: 1%", 1, true) ~= nil).toBe(true)
			expect(string.find(all, "Huge ×3: 0.5%", 1, true) ~= nil).toBe(true)
			expect(string.find(all, "Starborn ×2: Starfall Saturday only", 1, true) ~= nil).toBe(true)
			expect(string.find(all, "20% of spawns get the weather form", 1, true) ~= nil).toBe(true)
			c.Prefs._onSettings({ lang = "fr" })
			frames(c, 2)
			texts = {}
			for _, child in list:GetChildren() do
				if child:IsA("TextLabel") then
					table.insert(texts, child.Text)
				end
			end
			all = table.concat(texts, "\n")
			expect(string.find(all, "Géant ×3 : 0,5 %", 1, true) ~= nil).toBe(true)
		end)
	end)

	-- ==========================================================================================
	describe("Panels › Objectifs", function()
		local function quests(list, rerolls)
			return { day = TODAY, list = list, rerolls = rerolls or 0, starClaimed = false }
		end

		it("Aujourd'hui : 3 quêtes, progression, Réclamer et Relancer", function()
			local c = setup({
				idleRate = 10,
				quests = quests({
					{ id = 1, p = 10, done = false, claimed = false },
					{ id = 9, p = 15, done = true, claimed = false },
					{ id = 18, p = 25, done = true, claimed = true },
				}),
			})
			c.PC.open("Goals", { tab = "today" })
			local G = panel(c, "Goals")
			local cards = G._questCards
			expect(cards[1].title.Text).toBe("Catch Nebbies")
			expect(cards[1].desc.Text).toBe("Catch 40 Nebbies")
			expect(cards[1].progress.Text).toBe("10/40")
			expect(cards[1].reward.Text).toBe("≈ 1.8K Glow + 40 Stardust")
			expect(cards[1].reroll.Visible).toBe(true)
			expect(cards[2].claim.Visible).toBe(true)
			expect(cards[3].check.Visible).toBe(true)
			click(cards[2].claim)
			click(cards[2].claim) -- double appui : un seul envoi
			local claims = sent(c, "ClaimQuest")
			expect(#claims).toBe(1)
			expect(claims[1][1]).toBe("daily")
			expect(claims[1][2]).toBe(2)
			click(cards[1].reroll)
			expect(sent(c, "RerollQuest")[1][1]).toBe(1)
			expect(G.hasAction()).toBe(true)
		end)

		it("plus de relance (non VIP) et liste périmée : rien à relancer, message d'attente", function()
			local c = setup({ quests = quests({ { id = 1, p = 0, done = false, claimed = false } }, 1) })
			c.PC.open("Goals", { tab = "today" })
			local G = panel(c, "Goals")
			expect(G._questCards[1].reroll.Visible).toBe(false)
			patch(
				c,
				{ quests = { day = TODAY - 1, list = { { id = 2, p = 0, done = true, claimed = false } } } }
			)
			frames(c, 2)
			expect(G._questCards[1].frame.Visible).toBe(false)
			expect(c.PC.page("Goals").Body.Tab_today.List.Empty.Visible).toBe(true)
			expect(G.hasAction()).toBe(false)
		end)

		it(
			"Calendrier : carte du jour réclamable → ClaimDaily ; déjà réclamé → « Reviens demain »",
			function()
				local c = setup({ daily = { day = TODAY - 3, step = 3 }, idleRate = 0 })
				c.PC.open("Goals", { tab = "calendar" })
				local G = panel(c, "Goals")
				expect(G._dayCards[1].check.Visible).toBe(true)
				expect(G._dayCards[3].day.Text).toBe("Today")
				expect(G._dayCards[5].reward.Text).toBe("Daybreak Puff")
				expect(G._dayCards[1].reward.Text).toBe("≈ 500 Glow")
				local claim = G._calendarClaim()
				expect(claim.Visible).toBe(true)
				click(claim)
				expect(#sent(c, "ClaimDaily")).toBe(1)
				patch(c, { daily = { day = TODAY, step = 4 } })
				c.ScreenFX.Celebrated:Fire({ kind = "dailyClaimed", data = { day = 3, stardust = 0 } })
				frames(c, 10)
				expect(claim.Visible).toBe(false)
				expect(G._dayCards[3].check.Visible).toBe(true)
				expect(c.PC.page("Goals").Body.Tab_calendar.Tomorrow.Visible).toBe(true)
			end
		)

		it("Semaine : Grand Défilé réclamable à 300, sinon bouton inactif", function()
			local week = math.floor((T0 - 345600) / 604800)
			local c = setup({ weekly = { week = week, banked = 120, claimed = false } })
			c.PC.open("Goals", { tab = "week" })
			local G = panel(c, "Goals")
			expect(G._week.progress.Text).toBe("120/300")
			click(G._week.claim)
			expect(#sent(c, "ClaimQuest")).toBe(0)
			patch(c, { weekly = { week = week, banked = 300, claimed = false } })
			frames(c, 2)
			click(G._week.claim)
			local claims = sent(c, "ClaimQuest")
			expect(claims[1][1]).toBe("weekly")
			expect(claims[1][2]).toBe(1)
			expect(G.hasAction()).toBe(true)
		end)

		it("Accueil : quête en cours avec progression, faites cochées", function()
			local c = setup({ onboarding = { step = 3, p = 2 } })
			c.PC.open("Goals", { tab = "welcome" })
			local rows = panel(c, "Goals")._welcomeRows
			expect(rows[1].status.Text).toBe("✓")
			expect(rows[3].status.Text).toBe("▶")
			expect(rows[3].progress.Text).toBe("2/6")
			expect(rows[3].title.Text).toBe("Parade of 6")
			expect(rows[4].reward.Text).toBe("100 Stardust + Star Atlas")
			expect(rows[5].progress.Visible).toBe(false)
		end)
	end)

	-- ==========================================================================================
	describe("Panels › Boutique", function()
		local function withIds(c)
			c.Monetization.Passes.VIPStar.id = 111
			c.Monetization.Passes.NightShift.id = 112
			c.Monetization.Products.GlowPouch.id = 221
			c.Monetization.Products.GlowParty.id = 222
			c.Monetization.Products.StarterKit.id = 223
		end

		it("articles à id 0 masqués : boutique vide, aucune pastille", function()
			local c = setup({})
			c.PC.open("Shop")
			local S = panel(c, "Shop")
			local passes, products = S._rows()
			for _, row in passes do
				expect(row.frame.Visible).toBe(false)
			end
			expect(c.PC.page("Shop").Body.Tab_passes.Empty.Visible).toBe(true)
			expect(S.hasAction()).toBe(false)
			c.PC.nextTab(1)
			for _, row in products do
				expect(row.frame.Visible).toBe(false)
			end
		end)

		it(
			"passes : prix réel (Prices), achat → PromptGamePassPurchase, possédé → aucun prompt",
			function()
				local c = setup({ passes = { NightShift = true } }, withIds)
				c.PC.open("Shop", { tab = "passes" })
				c.h:settle(2)
				local passes = panel(c, "Shop")._rows()
				local vip, night
				for _, row in passes do
					if row.key == "VIPStar" then
						vip = row
					elseif row.key == "NightShift" then
						night = row
					end
				end
				expect(vip.frame.Visible).toBe(true)
				expect(vip.buy.Label.Text).toBe("R$ 99")
				click(vip.buy)
				expect(#c.h.log.prompts).toBe(1)
				expect(c.h.log.prompts[1].kind).toBe("pass")
				expect(c.h.log.prompts[1].id).toBe(111)
				expect(night.buy.Label.Text).toBe("✓ Owned")
				c.Clock.advance(2)
				click(night.buy)
				expect(#c.h.log.prompts).toBe(1)
			end
		)

		it(
			"produits : montant « ≈ », Glow Party masquée au-delà de 20 min, Starter Kit une fois",
			function()
				local c = setup({ idleRate = 10 }, withIds)
				local party = { endsAt = T0 + 600, source = "glowParty" }
				c.WSC.events = function()
					return {
						t = T0,
						serverBoost = party,
						wisps = {},
						snipsDisabled = false,
						activePlayers = 1,
					}
				end
				c.PC.open("Shop", { tab = "boosts" })
				local _, products = panel(c, "Shop")._rows()
				local byKey = {}
				for _, row in products do
					byKey[row.key] = row
				end
				expect(byKey.GlowPouch.detail.Text).toBe("≈ 6K Glow")
				expect(byKey.GlowParty.frame.Visible).toBe(true)
				expect(byKey.GlowParty.detail.Text).toBe("Party queued: 10m")
				expect(byKey.StarterKit.detail.Text).toBe("Once per account")
				click(byKey.GlowPouch.buy)
				expect(c.h.log.prompts[1].kind).toBe("product")
				expect(c.h.log.prompts[1].id).toBe(221)
				party.endsAt = T0 + 1500
				frames(c, 25)
				expect(byKey.GlowParty.frame.Visible).toBe(false)
				patch(c, { starterKit = true })
				frames(c, 2)
				expect(byKey.StarterKit.frame.Visible).toBe(false)
			end
		)

		it("codes : normalisés et envoyés une fois ; saisies invalides jamais envoyées", function()
			local c = setup({})
			local received = {}
			c.h:find(REMOTES .. "RedeemCode").OnServerInvoke = function(_, code)
				table.insert(received, code)
				return "ok"
			end
			c.PC.open("Shop", { tab = "codes" })
			local S = panel(c, "Shop")
			local box = S._codeBox()
			for _, bad in { "", "   ", "!!!", "abc-12", string.rep("A", 21) } do
				box.Text = bad
				S._redeem()
			end
			c.h:settle(2)
			expect(#received).toBe(0)
			expect(S._status().Text).toBe("Unknown code")
			box.Text = "  lumora 2026 "
			S._redeem()
			c.h:settle(2)
			expect(received).toEqual({ "LUMORA2026" })
			expect(S._status().Text).toBe("Code redeemed!")
			expect(box.Text).toBe("")
		end)

		it("codes : réponse serveur inattendue ou erreur → « Réessaie », pas de plantage", function()
			local c = setup({})
			local remote = c.h:find(REMOTES .. "RedeemCode")
			remote.OnServerInvoke = function()
				return { "hack" }
			end
			c.PC.open("Shop", { tab = "codes" })
			local S = panel(c, "Shop")
			S._codeBox().Text = "CODE1"
			S._redeem()
			c.h:settle(2)
			expect(S._status().Text).toBe("Try again in a moment")
			remote.OnServerInvoke = function()
				error("server down")
			end
			S._redeem()
			c.h:settle(2)
			expect(S._status().Text).toBe("Try again in a moment")
		end)
	end)

	-- ==========================================================================================
	describe("Panels › Équipage", function()
		it("liste des joueurs, Inviter limité à 1 / 3 s et 5 / min", function()
			local c = setup({})
			local players = {}
			for id = 2, 8 do
				players[id] = c.h:addPlayer({ userId = id, name = "P" .. id })
			end
			c.PC.open("Crew")
			frames(c, 2)
			local Crew = panel(c, "Crew")
			local rows = Crew._rowsByUser
			expect(rows[2].name.Text).toBe("P2")
			expect(rows[2].invite.Visible).toBe(true)
			click(rows[2].invite)
			click(rows[3].invite) -- moins de 3 s après
			expect(#sent(c, "CrewInvite")).toBe(1)
			expect(sent(c, "CrewInvite")[1][1]).toBe(2)
			expect(rows[2].tag.Text).toBe("Sent!")
			for id = 3, 7 do
				c.Clock.advance(3.1)
				Crew.invite(id)
			end
			expect(#sent(c, "CrewInvite")).toBe(5) -- 5 / min
			c.Clock.advance(60)
			Crew.invite(8)
			expect(#sent(c, "CrewInvite")).toBe(6)
		end)

		it("charges absurdes : aucune invitation", function()
			local c = setup({})
			c.PC.open("Crew")
			local Crew = panel(c, "Crew")
			for _, bad in { "x", nil, 0 / 0, 1, 999, {} } do
				Crew.invite(bad)
			end
			expect(#sent(c, "CrewInvite")).toBe(0)
		end)

		it("équipage : équipiers marqués, Quitter (recharge 5 s), équipage plein", function()
			local c = setup({})
			for id = 2, 5 do
				c.h:addPlayer({ userId = id, name = "P" .. id })
			end
			local crew = { 1, 2 }
			c.WSC.crews = function()
				return { crews = { { id = 1, userIds = crew } } }
			end
			c.PC.open("Crew")
			frames(c, 2)
			local Crew = panel(c, "Crew")
			local rows = Crew._rowsByUser
			expect(rows[2].tag.Text).toBe("★ Crewmate")
			expect(rows[2].invite.Visible).toBe(false)
			local leave = c.PC.page("Crew").Body.Leave
			expect(leave.Visible).toBe(true)
			click(leave)
			click(leave)
			expect(#sent(c, "CrewLeave")).toBe(1)
			crew = { 1, 2, 3, 4 }
			c.WSC.CrewsChanged:Fire({ crews = { { id = 1, userIds = crew } } })
			frames(c, 2)
			click(rows[5].invite)
			expect(#sent(c, "CrewInvite")).toBe(0)
		end)

		it("un joueur qui part disparaît de la liste", function()
			local c = setup({})
			local p2 = c.h:addPlayer({ userId = 2, name = "P2" })
			c.PC.open("Crew")
			frames(c, 2)
			local rows = panel(c, "Crew")._rowsByUser
			expect(rows[2] ~= nil).toBe(true)
			c.h:removePlayer(p2)
			frames(c, 2)
			expect(rows[2]).toBeNil()
		end)

		it(
			"carte d'invitation : ✓ → CrewRespond(id, true), file d'attente, expirées ignorées",
			function()
				local c = setup({})
				c.h:addPlayer({ userId = 2, name = "Mira" })
				c.h:addPlayer({ userId = 3, name = "Noah" })
				c.h:addPlayer({ userId = 4, name = "Léa" })
				local Crew = panel(c, "Crew")
				Crew.showInvite({ inviterId = 2, expiresAt = T0 + 20 })
				Crew.showInvite({ inviterId = 3, expiresAt = T0 + 20 })
				Crew.showInvite({ inviterId = 4, expiresAt = T0 + 5 })
				expect(Crew.hasAction()).toBe(true)
				local card = Crew._card()
				click(card.Accept)
				local responses = sent(c, "CrewRespond")
				expect(responses[1][1]).toBe(2)
				expect(responses[1][2]).toBe(true)
				expect(Crew._shown().inviterId).toBe(3)
				expect(card.Text.Text).toBe("Noah invites you!")
				c.Clock.advance(10) -- l'invitation de Léa expire
				click(card.Decline)
				responses = sent(c, "CrewRespond")
				expect(responses[2][1]).toBe(3)
				expect(responses[2][2]).toBe(false)
				expect(Crew._shown()).toBeNil()
				expect(card.Visible).toBe(false)
				expect(#sent(c, "CrewRespond")).toBe(2)
			end
		)

		it("Inviter un ami → SocialService:PromptGameInvite", function()
			local c = setup({})
			c.PC.open("Crew")
			click(c.PC.page("Crew").Body.InviteFriend)
			c.h:settle(2)
			expect(#c.h.log.invites).toBe(1)
		end)
	end)

	-- ==========================================================================================
	describe("Panels › Réglages", function()
		it(
			"lignes générées depuis Config/Settings ; Coupes désactivées masquées hors serveur privé",
			function()
				local c = setup({})
				c.PC.open("Settings")
				local rows = panel(c, "Settings")._rows
				local n = 0
				for _ in rows do
					n += 1
				end
				expect(n).toBe(9)
				expect(rows.privateNoSnip.frame.Visible).toBe(false)
				expect(rows.music.name.Text).toBe("Music")
				expect(rows.music.toggle:GetAttribute("On")).toBe(true)
			end
		)

		it("interrupteur optimiste → SetSetting, puis retour si le serveur refuse", function()
			local c = setup({})
			c.PC.open("Settings")
			local S = panel(c, "Settings")
			click(S._rows.music.toggle)
			local sets = sent(c, "SetSetting")
			expect(sets[1][1]).toBe("music")
			expect(sets[1][2]).toBe(false)
			expect(S._rows.music.toggle:GetAttribute("On")).toBe(false)
			frames(c, 60) -- 3 s sans confirmation du profil
			expect(S._rows.music.toggle:GetAttribute("On")).toBe(true)
		end)

		it("Mode Zen : seulement au port sûr, puis recharge de 60 s affichée", function()
			local c = setup({})
			goAway(c)
			c.PC.open("Settings")
			local S = panel(c, "Settings")
			frames(c, 12)
			expect(S._rows.zen.status.Text).toBe("Only in your Nest's safe harbor")
			click(S._rows.zen.toggle)
			expect(#sent(c, "SetSetting")).toBe(0)
			goHome(c)
			frames(c, 12)
			click(S._rows.zen.toggle)
			expect(#sent(c, "SetSetting")).toBe(1)
			patch(c, { settings = { zen = true, lang = "en" } })
			frames(c, 12)
			click(S._rows.zen.toggle)
			expect(#sent(c, "SetSetting")).toBe(1)
			expect(string.find(S._rows.zen.status.Text, "Available again in", 1, true) ~= nil).toBe(true)
			c.Clock.advance(61)
			frames(c, 12)
			click(S._rows.zen.toggle)
			expect(#sent(c, "SetSetting")).toBe(2)
		end)

		it("langue → SetSetting(lang) ; valeurs et clés invalides jamais envoyées", function()
			local c = setup({})
			c.PC.open("Settings")
			local S = panel(c, "Settings")
			click(S._rows.lang.choices.fr)
			expect(sent(c, "SetSetting")[1][1]).toBe("lang")
			expect(sent(c, "SetSetting")[1][2]).toBe("fr")
			for _, args in
				{ { "lang", "xx" }, { "unknown", true }, { "music", "yes" }, { "music", 1 }, { {}, true } }
			do
				S.setSetting(args[1], args[2])
			end
			expect(#sent(c, "SetSetting")).toBe(1)
		end)

		it("Coupes désactivées : propriétaire du serveur privé seulement", function()
			local c = setup({})
			c.h.game.PrivateServerOwnerId = 1
			c.PC.open("Settings")
			local S = panel(c, "Settings")
			frames(c, 2)
			expect(S._rows.privateNoSnip.frame.Visible).toBe(true)
			click(S._rows.privateNoSnip.toggle)
			expect(sent(c, "SetSetting")[1][1]).toBe("privateNoSnip")
			expect(sent(c, "SetSetting")[1][2]).toBe(true)
		end)

		it("styles : seulement les cosmétiques possédés → EquipCosmetic", function()
			local c = setup({
				unlocks = { styles = { constellation = true }, titles = {}, themes = {} },
				passes = { VIPStar = true },
			})
			c.PC.open("Settings")
			local S = panel(c, "Settings")
			local styles = S._styleRows[1]
			expect(styles.chips.default ~= nil).toBe(true)
			expect(styles.chips.constellation ~= nil).toBe(true)
			expect(styles.chips.royal_star ~= nil).toBe(true)
			expect(styles.chips.ember).toBeNil()
			click(styles.chips.constellation)
			local equips = sent(c, "EquipCosmetic")
			expect(equips[1][1]).toBe("style")
			expect(equips[1][2]).toBe("constellation")
			local titles = S._styleRows[2]
			expect(titles.chips[""] ~= nil).toBe(true)
			expect(titles.chips.cartographer).toBeNil()
			local themes = S._styleRows[3]
			expect(themes.chips.royal_gold ~= nil).toBe(true)
		end)

		it("LiveOps visible seulement pour un Admin → AdminCommand (limité)", function()
			local c = setup({})
			c.PC.open("Settings")
			local S = panel(c, "Settings")
			expect(S._liveOpsFrame().Visible).toBe(false)
			click(S._liveOps.comet)
			expect(#sent(c, "AdminCommand")).toBe(0)
			c.h.localPlayer:SetAttribute("Admin", true)
			c.h:settle(1)
			expect(S._liveOpsFrame().Visible).toBe(true)
			click(S._liveOps.comet)
			click(S._liveOps["weather:aurora"])
			local cmds = sent(c, "AdminCommand")
			expect(#cmds).toBe(1)
			expect(cmds[1][1]).toBe("comet")
			c.Clock.advance(2.5)
			click(S._liveOps["weather:aurora"])
			expect(sent(c, "AdminCommand")[2][1]).toBe("weather:aurora")
		end)
	end)

	-- ==========================================================================================
	describe("Panels › Écran de retour", function()
		it("compteur 0 → gain en 0,8 s, durée d'absence, bouton Super !", function()
			local c = setup({})
			local RS = panel(c, "ReturnScreen")
			RS.present({ glow = 1240000, seconds = 18720, nightShift = false })
			expect(c.PC.current()).toBe("ReturnScreen")
			expect(RS._amount().Text).toBe("+0 Glow")
			frames(c, 20)
			expect(RS._amount().Text).toBe("+1.24M Glow")
			local body = c.PC.page("ReturnScreen").Body
			expect(body.Title.Text).toBe("While you were away (5h 12m)")
			expect(body.Ok.Size.Y.Offset).toBe(96)
			click(body.Ok)
			expect(c.PC.current()).toBeNil()
		end)

		it("ligne Night Shift discrète : seulement si le pass est en vente et non possédé", function()
			local c = setup({})
			local RS = panel(c, "ReturnScreen")
			RS.present({ glow = 5000, seconds = 600 })
			expect(RS._nightShift().Visible).toBe(false) -- id 0
			c.Monetization.Passes.NightShift.id = 777
			RS.present({ glow = 5000, seconds = 600 })
			expect(RS._nightShift().Visible).toBe(true)
			patch(c, { passes = { NightShift = true } })
			frames(c, 2)
			expect(RS._nightShift().Visible).toBe(false)
		end)

		it("données malformées : valeurs sûres, jamais d'erreur", function()
			local c = setup({})
			local RS = panel(c, "ReturnScreen")
			RS.present("x")
			expect(c.PC.current()).toBeNil()
			RS.present({ glow = 0 / 0, seconds = -50 })
			frames(c, 20)
			expect(RS._data().glow).toBe(0)
			expect(RS._data().seconds).toBe(0)
			RS.present({ glow = math.huge, seconds = "x" })
			expect(RS._data().glow).toBe(0)
		end)

		it("Mouvement réduit : montant final tout de suite, pas de fontaine", function()
			local c = setup({ settings = { reducedMotion = true, lang = "en" } })
			local RS = panel(c, "ReturnScreen")
			RS.present({ glow = 2500, seconds = 60 })
			expect(RS._amount().Text).toBe("+2.5K Glow")
		end)
	end)

	-- ==========================================================================================
	describe("Panels › langue", function()
		it("chaque panneau ouvert ré-applique ses textes en français", function()
			local c = setup({ glow = 100 })
			c.PC.open("Upgrades")
			local U = panel(c, "Upgrades")
			expect(U._cards.stride.name.Text).toBe("Stride")
			c.Prefs._onSettings({ lang = "fr" })
			frames(c, 2)
			expect(U._cards.stride.name.Text).toBe("Foulée")
			expect(U._cards.conga.effect.Text).toBe("3 → 4 places")
			expect(c.PC.page("Upgrades").Header.Title.Text).toBe("Améliorer")
		end)
	end)

	-- ==========================================================================================
	-- Revue du paquet : chaque test reproduit un défaut trouvé, corrigé ensuite
	describe("Panels › revue (défauts corrigés)", function()
		local function uis(c)
			return c.h.game.UserInputService
		end

		it("Supernova : doigt relevé HORS du bouton (InputEnded global) → maintien annulé", function()
			local c = setup({ glow = 400000 })
			goHome(c)
			c.PC.open("Supernova")
			local S = panel(c, "Supernova")
			S._refs.hold.MouseButton1Down:Fire()
			frames(c, 6)
			expect(S._holding()).toBe(true)
			-- le doigt a glissé hors du bouton : ni MouseButton1Up ni MouseLeave sur le bouton
			uis(c).InputEnded:Fire({ UserInputType = Enum.UserInputType.Touch }, false)
			frames(c, 30)
			expect(S._holding()).toBe(false)
			expect(#sent(c, "Supernova")).toBe(0)
		end)

		it("Supernova : un AUTRE doigt relevé (joystick) n'annule pas le maintien tactile", function()
			local c = setup({ glow = 400000 })
			goHome(c)
			c.PC.open("Supernova")
			local S = panel(c, "Supernova")
			local finger = { UserInputType = Enum.UserInputType.Touch }
			local joystick = { UserInputType = Enum.UserInputType.Touch }
			S._refs.hold.InputBegan:Fire(finger)
			S._refs.hold.MouseButton1Down:Fire()
			frames(c, 6)
			uis(c).InputEnded:Fire(joystick, false)
			frames(c, 4)
			expect(S._holding()).toBe(true)
			uis(c).InputEnded:Fire(finger, false)
			frames(c, 30)
			expect(S._holding()).toBe(false)
			expect(#sent(c, "Supernova")).toBe(0)
		end)

		it("Supernova : maintien à la manette (A sur le bouton sélectionné), relâcher annule", function()
			local c = setup({ glow = 400000 })
			goHome(c)
			c.PC.open("Supernova")
			local S = panel(c, "Supernova")
			local gs = c.h.game.GuiService
			gs.SelectedObject = S._refs.hold
			local a = { UserInputType = Enum.UserInputType.Gamepad1, KeyCode = Enum.KeyCode.ButtonA }
			uis(c).InputBegan:Fire(a, true)
			frames(c, 8)
			uis(c).InputEnded:Fire(a, true)
			frames(c, 30)
			expect(#sent(c, "Supernova")).toBe(0)
			uis(c).InputBegan:Fire(a, true)
			frames(c, 24)
			expect(#sent(c, "Supernova")).toBe(1)
			-- A sans que le bouton soit sélectionné : rien
			gs.SelectedObject = nil
			c.Clock.advance(3)
			c.PC.open("Supernova")
			uis(c).InputBegan:Fire(a, true)
			frames(c, 30)
			expect(#sent(c, "Supernova")).toBe(1)
		end)

		it(
			"Réserve : la case réutilisée pour un autre Nebby annule le rétrécissement en cours",
			function()
				local nebbies = {}
				for i = 1, 12 do
					nebbies["u" .. i] = neb(1)
				end
				local c = setup({ nebbies = nebbies })
				c.PC.open("Collection", { tab = "stash" })
				local C = panel(c, "Collection")
				local Juice = c.h:require(CLIENT .. "UI.Juice")
				local original = Juice.tween
				local shrinks = {}
				-- tween de rétrécissement « en cours » : il n'écrit jamais sa valeur finale tout seul
				Juice.tween = function(inst, duration, props, ...)
					if props.Scale == 0 and duration == 0.2 then
						local fake = { cancelled = false, inst = inst }
						function fake.Cancel(self)
							self.cancelled = true
						end
						table.insert(shrinks, fake)
						inst.Scale = 0
						return fake
					end
					return original(inst, duration, props, ...)
				end
				local st = C._state()
				local first = st.sorted[1]
				local cell
				for _, candidate in st.grid:cells() do
					if candidate:GetAttribute("Uid") == first then
						cell = candidate
					end
				end
				C._tap(cell)
				C._release()
				C._release()
				expect(#sent(c, "Release")).toBe(1)
				expect(#shrinks).toBe(1)
				local scale = shrinks[1].inst
				-- le serveur retire le Nebby : la case affiche maintenant un autre uid
				local rest = table.clone(nebbies)
				rest[first] = nil
				patch(c, { nebbies = rest })
				frames(c, 2)
				expect(cell:GetAttribute("Uid") ~= first).toBe(true)
				expect(shrinks[1].cancelled).toBe(true)
				expect(scale.Scale).toBe(1)
				Juice.tween = original
			end
		)

		it("Guide : pas reconstruit à chaque changement du profil (seulement à la langue)", function()
			local c = setup({ idleRate = 5 })
			c.PC.open("Collection", { tab = "guide" })
			local list = c.PC.page("Collection").Body.Tab_guide.List
			local line = list:FindFirstChild("Line1")
			expect(line ~= nil).toBe(true)
			patch(c, { idleRate = 50, stardust = 10 })
			frames(c, 3)
			expect(line.Parent).toBe(list)
			c.Prefs._onSettings({ lang = "fr" })
			frames(c, 2)
			expect(list:FindFirstChild("Line1").Text ~= line.Text or line.Parent == nil).toBe(true)
		end)

		it("Atlas : fiche d'espèce avec rareté, zones et meilleur exemplaire possédé (§4.14)", function()
			local c = setup({
				onboarding = { step = 8, p = 0 },
				atlas = { 1, 0, 0, 0, 0, 0, 0 },
				nebbies = { u1 = neb(1, 0, 0, 3), u2 = neb(1) },
			})
			local Nebbies = c.h:require("ReplicatedStorage.Shared.Config.Nebbies")
			c.PC.open("Collection", { tab = "atlas" })
			local row = c.PC.page("Collection").Body.Tab_atlas.List.Species1
			local detail = row:FindFirstChild("Detail")
			expect(detail ~= nil).toBe(true)
			local rarityKey = Nebbies.Rarities[Nebbies.rarityOf(1)].key
			expect(string.find(detail.Text, c.Prefs.t("rarity." .. rarityKey), 1, true) ~= nil).toBe(true)
			expect(string.find(detail.Text, "★★★", 1, true) ~= nil).toBe(true)
			-- espèce jamais possédée : rareté, sans meilleur exemplaire
			local other = c.PC.page("Collection").Body.Tab_atlas.List.Species2
			expect(string.find(other.Detail.Text, "★", 1, true)).toBeNil()
		end)

		it(
			"Équipage : la même invitation renouvelée prolonge la carte ; expiration à l'horloge",
			function()
				local c = setup({})
				c.h:addPlayer({ userId = 2, name = "Mira" })
				local Crew = panel(c, "Crew")
				Crew.showInvite({ inviterId = 2, expiresAt = T0 + 20 })
				c.Clock.advance(10)
				frames(c, 2)
				Crew.showInvite({ inviterId = 2, expiresAt = T0 + 30 })
				c.Clock.advance(12) -- T0 + 22 : l'ancienne échéance est passée
				frames(c, 2)
				expect(Crew._shown() ~= nil).toBe(true)
				expect(Crew._card().Visible).toBe(true)
				c.Clock.advance(9) -- T0 + 31
				frames(c, 2)
				expect(Crew._shown()).toBeNil()
				expect(Crew._card().Visible).toBe(false)
			end
		)

		it("Équipage : l'inviteur quitte le serveur → carte retirée (panneau jamais ouvert)", function()
			local c = setup({})
			local mira = c.h:addPlayer({ userId = 2, name = "Mira" })
			c.h:addPlayer({ userId = 3, name = "Noah" })
			local Crew = panel(c, "Crew")
			Crew.showInvite({ inviterId = 2, expiresAt = T0 + 20 })
			Crew.showInvite({ inviterId = 3, expiresAt = T0 + 20 })
			c.h:removePlayer(mira)
			frames(c, 2)
			expect(Crew._shown().inviterId).toBe(3)
			click(Crew._card().Accept)
			expect(sent(c, "CrewRespond")[1][1]).toBe(3)
		end)

		it("Équipage : panneau ouvert, « Inviter » revient après 20 s et Quitter après 5 s", function()
			local c = setup({})
			c.h:addPlayer({ userId = 2, name = "P2" })
			c.WSC.crews = function()
				return { crews = { { id = 1, userIds = { 1, 3 } } } }
			end
			c.h:addPlayer({ userId = 3, name = "P3" })
			c.PC.open("Crew")
			frames(c, 2)
			local Crew = panel(c, "Crew")
			local rows = Crew._rowsByUser
			click(rows[2].invite)
			expect(rows[2].invite.Visible).toBe(false)
			local leave = c.PC.page("Crew").Body.Leave
			click(leave)
			expect(#sent(c, "CrewLeave")).toBe(1)
			frames(c, 120) -- 6 s
			expect(leave:GetAttribute("Disabled")).toBe(false)
			frames(c, 300) -- 21 s au total
			expect(rows[2].invite.Visible).toBe(true)
		end)

		it("Équipage : le rafraîchissement périodique ne recrée pas les puces des membres", function()
			local c = setup({})
			c.h:addPlayer({ userId = 2, name = "P2" })
			local crew = { 1, 2 }
			c.WSC.crews = function()
				return { crews = { { id = 1, userIds = crew } } }
			end
			c.PC.open("Crew")
			frames(c, 2)
			local members = c.PC.page("Crew").Body.Members
			local chip = members:FindFirstChild("Member2")
			expect(chip ~= nil).toBe(true)
			frames(c, 50) -- 2,5 s : deux rafraîchissements
			expect(chip.Parent).toBe(members)
			c.h:addPlayer({ userId = 3, name = "P3" })
			crew = { 1, 2, 3 }
			c.WSC.CrewsChanged:Fire({ crews = { { id = 1, userIds = crew } } })
			frames(c, 2)
			expect(members:FindFirstChild("Member3") ~= nil).toBe(true)
		end)

		it("Réglages : le rendu périodique ne relance pas l'animation des interrupteurs", function()
			local c = setup({})
			c.PC.open("Settings")
			local Juice = c.h:require(CLIENT .. "UI.Juice")
			local original = Juice.tween
			local knobs = 0
			Juice.tween = function(inst, duration, props, ...)
				if inst.Name == "Knob" then
					knobs += 1
				end
				return original(inst, duration, props, ...)
			end
			frames(c, 40) -- 2 s : 4 rendus
			expect(knobs).toBe(0)
			click(panel(c, "Settings")._rows.music.toggle)
			expect(knobs).toBe(1)
			Juice.tween = original
		end)

		it("Équipage plein : Inviter refusé avec un toast explicite", function()
			local c = setup({})
			for id = 2, 5 do
				c.h:addPlayer({ userId = id, name = "P" .. id })
			end
			c.WSC.crews = function()
				return { crews = { { id = 1, userIds = { 1, 2, 3, 4 } } } }
			end
			c.PC.open("Crew")
			frames(c, 2)
			click(panel(c, "Crew")._rowsByUser[5].invite)
			expect(#sent(c, "CrewInvite")).toBe(0)
			expect(#toasts(c)).toBe(1)
		end)

		it("Zen : un refus serveur ne bloque pas 60 s ; la recharge part de la confirmation", function()
			local c = setup({})
			goHome(c)
			c.PC.open("Settings")
			local S = panel(c, "Settings")
			click(S._rows.zen.toggle)
			expect(#sent(c, "SetSetting")).toBe(1)
			-- double appui pendant l'attente de confirmation : un seul envoi
			click(S._rows.zen.toggle)
			expect(#sent(c, "SetSetting")).toBe(1)
			-- le serveur refuse (aucun patch) : après le délai d'attente, on peut réessayer
			frames(c, 60)
			expect(S._rows.zen.status.Text).toBe("")
			click(S._rows.zen.toggle)
			expect(#sent(c, "SetSetting")).toBe(2)
			patch(c, { settings = { zen = true, lang = "en" } })
			frames(c, 12)
			click(S._rows.zen.toggle)
			expect(#sent(c, "SetSetting")).toBe(2)
			expect(string.find(S._rows.zen.status.Text, "Available again in", 1, true) ~= nil).toBe(true)
		end)

		it(
			"Boutique : Glow Party masquée si un autre ×2 de serveur dépasse 20 min (file serveur)",
			function()
				local c = setup({ idleRate = 10 }, function(cc)
					cc.Monetization.Products.GlowParty.id = 222
				end)
				local boost = { endsAt = T0 + 1500, source = "starfall" }
				c.WSC.events = function()
					return {
						t = T0,
						serverBoost = boost,
						wisps = {},
						snipsDisabled = false,
						activePlayers = 1,
					}
				end
				c.PC.open("Shop", { tab = "boosts" })
				local _, products = panel(c, "Shop")._rows()
				local party
				for _, row in products do
					if row.key == "GlowParty" then
						party = row
					end
				end
				expect(party.frame.Visible).toBe(false)
				boost.endsAt = T0 + 600
				frames(c, 25)
				expect(party.frame.Visible).toBe(true)
				expect(string.find(party.detail.Text, "Starts after the current ×2: ", 1, true)).toBe(1)
				expect(
					c.Model.glowPartyRemaining({ serverBoost = { endsAt = T0 + 90, source = "liveOps" } }, T0)
				).toBe(90)
			end
		)

		it("Objectifs : la barre de quête se remplit en 0,3 s quand la progression monte", function()
			local function q(p)
				return {
					day = TODAY,
					list = { { id = 1, p = p, done = false, claimed = false } },
					rerolls = 0,
					starClaimed = false,
				}
			end
			local c = setup({ quests = q(10) })
			c.PC.open("Goals", { tab = "today" })
			local Juice = c.h:require(CLIENT .. "UI.Juice")
			local original = Juice.tween
			local fills = 0
			Juice.tween = function(inst, duration, props, ...)
				if inst.Name == "Fill" and duration == 0.3 then
					fills += 1
				end
				return original(inst, duration, props, ...)
			end
			patch(c, { quests = q(20) })
			frames(c, 2)
			expect(fills).toBe(1)
			patch(c, { quests = q(20) })
			frames(c, 2)
			expect(fills).toBe(1)
			Juice.tween = original
		end)

		it("Améliorer : pastille « ! » aussi quand seule la Supernova est payable", function()
			local c = setup({
				glow = 400000,
				upgrades = { conga = 12, stride = 20, lure = 12, perches = 27, guard = 5 },
			})
			local U = panel(c, "Upgrades")
			expect(#c.Model.affordableUpgrades(c.State.get("glow") and c.Model.view(c.State.get), T0)).toBe(0)
			expect(U.hasAction()).toBe(true)
		end)
	end)

	-- ==========================================================================================
	describe("Panels › Model (calculs purs)", function()
		local h = Harness.new({ mode = "client" })
		local Model = h:require(CLIENT .. "UI.Panels.Model")
		local Formulas = h:require("ReplicatedStorage.Shared.Logic.Formulas")

		it("Glow prédit borné, jamais sous la valeur serveur, robuste à NaN", function()
			expect(
				Model.predictedGlow({ glow = 100, idleRate = 2, lastSettle = T0 - 10, glowCarry = 0.5 }, T0)
			).toBe(120)
			expect(Model.predictedGlow({ glow = 100, idleRate = 2, lastSettle = T0 - 10000 }, T0)).toBe(230)
			expect(Model.predictedGlow({ glow = 100, idleRate = 2, lastSettle = T0 + 50 }, T0)).toBe(100)
			expect(Model.predictedGlow({ glow = 0 / 0, idleRate = math.huge, lastSettle = "x" }, T0)).toBe(0)
		end)

		it("tri des perchoirs : revenu, puis rareté, puis uid le plus ancien", function()
			local ranked = Model.rank({
				u10 = neb(1),
				u2 = neb(1),
				u3 = neb(9),
				u4 = neb(1, 1), -- Aurora ×2 = 2 Glow/s
				bad = neb(99),
				u5 = "x",
			})
			expect(ranked.uids).toEqual({ "u3", "u4", "u2", "u10" })
			expect(ranked.income.u3).toBe(4)
		end)

		it("groupes Starforge : copies non verrouillées, choix du verrouillé, coût", function()
			local groups = Model.fuseGroups({
				stardust = 30,
				nebbies = {
					u1 = neb(1, 0, 0, 1, true),
					u2 = neb(1),
					u3 = neb(1),
					u4 = neb(2),
					u5 = neb(2),
					u6 = neb(1, 0, 0, 5),
					u7 = neb(1, 0, 0, 5),
					u8 = neb(1, 0, 0, 5),
				},
			})
			expect(#groups).toBe(1)
			expect(groups[1].chosen).toBe("u1")
			expect(groups[1].fusable).toBe(true)
			expect(groups[1].affordable).toBe(true)
			expect(groups[1].cost).toBe(25)
			expect(groups[1].gain).toBe(Formulas.passiveIncome(neb(1, 0, 0, 2)) - 3)
		end)

		it("calendrier : réclamé, aujourd'hui, demain, semaine complète", function()
			local cal = Model.calendar({ daily = { day = TODAY - 1, step = 3 } }, TODAY)
			expect(cal[2].state).toBe("claimed")
			expect(cal[3].state).toBe("today")
			expect(cal[4].state).toBe("upcoming")
			cal = Model.calendar({ daily = { day = TODAY, step = 3 } }, TODAY)
			expect(cal[3].state).toBe("next")
			cal = Model.calendar({ daily = { day = TODAY, step = 1 } }, TODAY)
			expect(cal[7].state).toBe("claimed")
			cal = Model.calendar({ daily = { day = 0 / 0, step = 99 } }, TODAY)
			expect(cal[7].state).toBe("today")
		end)

		it("codes promo normalisés (majuscules, sans espaces, ≤ 20, alphanumériques)", function()
			expect(Model.normalizeCode(" ab c1 ")).toBe("ABC1")
			expect(Model.normalizeCode("")).toBeNil()
			expect(Model.normalizeCode("A-B")).toBeNil()
			expect(Model.normalizeCode(string.rep("x", 21))).toBeNil()
			expect(Model.normalizeCode(12)).toBeNil()
		end)

		it("aperçu de Supernova identique aux formules du serveur", function()
			local p = Model.supernovaPreview({ glow = 5, supernovas = 1 }, T0, true)
			expect(p.cost).toBe(Formulas.supernovaCost(1))
			expect(p.congaCapNext).toBe(Formulas.upgradeMaxLevel("conga", 2))
			expect(p.resets).toEqual({ "glow", "conga", "stride", "lure" })
			expect(p.keeps).toEqual({
				"nebbies",
				"perches",
				"guard",
				"stardust",
				"atlas",
				"cosmetics",
				"quests",
				"stats",
			})
			expect(p.canAfford).toBe(false)
		end)

		it("cosmétiques possédés : gratuit, déblocage, pass, statistique", function()
			local Cosmetics = h:require("ReplicatedStorage.Shared.Config.Cosmetics")
			local p = {
				passes = { CongaStyles = true },
				unlocks = { titles = { cartographer = true } },
				stats = { cometsBanked = 10 },
			}
			expect(Model.ownsCosmetic(p, "styles", Cosmetics.Styles, "default")).toBe(true)
			expect(Model.ownsCosmetic(p, "styles", Cosmetics.Styles, "ember")).toBe(true)
			expect(Model.ownsCosmetic(p, "styles", Cosmetics.Styles, "royal_star")).toBe(false)
			expect(Model.ownsCosmetic(p, "titles", Cosmetics.Titles, "cartographer")).toBe(true)
			expect(Model.ownsCosmetic(p, "titles", Cosmetics.Titles, "comet_hunter")).toBe(true)
			expect(Model.ownsCosmetic(p, "titles", Cosmetics.Titles, "beacon_keeper")).toBe(false)
			expect(Model.ownsCosmetic(p, "titles", Cosmetics.Titles, "nope")).toBe(false)
		end)
	end)
end
