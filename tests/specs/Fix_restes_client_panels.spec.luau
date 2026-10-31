--!nocheck
-- Correctifs « restes client-panels » :
--   * Q4 : le compteur de la Réserve compare les Nebbies NON perchés à la capacité de la réserve
--     (AtlasService.enforceStash : total − perchoirs − capacité) : 30 perchoirs + 330 Nebbies =
--     « 300/300 », jamais « 330/300 »
--   * N126/N127 : texte ≥ 18 px de référence (GDD §10.1) dans chaque panneau et chaque onglet ouvert
--     par PanelController (marcheur tooSmall/refSize de Fix_client-hud_r1, touches « KeyCap » à part)
--   * Q19 : « Ton Nid travaille même quand tu dors » + plafond hors ligne (8 h / 50 %, 12 h / 75 %
--     avec Night Shift) en pied du panneau Réglages (GDD §7.1), en anglais et en français
--   * N77 : Mode Zen actif avec une file non vide → interrupteur désactivé, ligne d'état
--     « fais parader ta file d'abord » (miroir de NestService : feedback.zenBankFirst), rien d'envoyé
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000
	local TODAY = math.floor(T0 / 86400)
	local MIN_TEXT = 18 -- px de référence (GDD §10.1)

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
			Clock = Clock,
			L = h:require("ReplicatedStorage.Shared.Localization"),
			Root = h:require(CLIENT .. "UI.Root"),
			State = h:require(CLIENT .. "Controllers.StateController"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			WSC = h:require(CLIENT .. "Controllers.WorldStateController"),
			ScreenFX = h:require(CLIENT .. "UI.ScreenFX"),
			PC = h:require(CLIENT .. "Controllers.PanelController"),
			WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
			Monetization = h:require("ReplicatedStorage.Shared.Config.Monetization"),
			Balance = h:require("ReplicatedStorage.Shared.Config.Balance"),
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

	local function goHome(c, slot)
		local me = c.h.localPlayer
		me:SetAttribute("Slot", slot or 1)
		local gate = c.WorldLayout.gateCFrame(slot or 1).Position
		me.Character.HumanoidRootPart.CFrame = CFrame.new(gate.X, 3, gate.Z)
	end

	-- ==========================================================================================
	-- Q4 : compteur de la Réserve
	-- ==========================================================================================
	describe("Fix restes client-panels › compteur de la Réserve (Q4)", function()
		-- `count` Nebbies communs ; perchoirs = Base 3 + niveau `perchLevel` + jalons d'Atlas (aucun)
		local function many(count)
			local nebbies = {}
			for i = 1, count do
				nebbies["u" .. i] = neb((i % 7) + 1)
			end
			return nebbies
		end

		it("30 perchoirs et 330 Nebbies : « 300/300 » (les perchés ne comptent pas)", function()
			local c = setup({
				nebbies = many(330),
				upgrades = { conga = 0, stride = 0, lure = 0, perches = 27, guard = 0 },
			})
			expect(c.Model.perchCount(c.Model.view(c.State.get))).toBe(30)
			c.PC.open("Collection", { tab = "stash" })
			local count = c.PC.page("Collection").Body.Tab_stash.Toolbar.Count
			expect(count.Text).toBe("300/300")
		end)

		it("réserve pas pleine : 30 perchoirs, 300 Nebbies → « 270/300 » (30 places libres)", function()
			local c = setup({
				nebbies = many(300),
				upgrades = { conga = 0, stride = 0, lure = 0, perches = 27, guard = 0 },
			})
			c.PC.open("Collection", { tab = "stash" })
			local count = c.PC.page("Collection").Body.Tab_stash.Toolbar.Count
			expect(count.Text).toBe("270/300")
			-- un Nebby de plus (profil répliqué) : le compteur suit
			local more = many(301)
			patch(c, { nebbies = more })
			frames(c, 2)
			expect(count.Text).toBe("271/300")
		end)

		it("moins de Nebbies que de perchoirs : « 0/300 », jamais négatif ; Stash Plus → /600", function()
			local c = setup({
				nebbies = many(2),
				upgrades = { conga = 0, stride = 0, lure = 0, perches = 27, guard = 0 },
				passes = { StashPlus = true },
			})
			c.PC.open("Collection", { tab = "stash" })
			local count = c.PC.page("Collection").Body.Tab_stash.Toolbar.Count
			expect(count.Text).toBe("0/600")
		end)
	end)

	-- ==========================================================================================
	-- N126 / N127 : texte ≥ 18 px de référence dans tous les panneaux (marcheur de Fix_client-hud_r1)
	-- ==========================================================================================

	-- taille de référence (écran 1280 × 720, échelle 1) en remontant la hiérarchie
	local function refSize(gui)
		if gui == nil or gui:IsA("ScreenGui") or gui:IsA("PlayerGui") then
			return 1280, 720
		end
		local pw, ph = refSize(gui.Parent)
		if not gui:IsA("GuiObject") then
			return pw, ph
		end
		return gui.Size.X.Scale * pw + gui.Size.X.Offset, gui.Size.Y.Scale * ph + gui.Size.Y.Offset
	end

	-- tous les libellés bornés trop petits (hors touches de raccourci)
	local function tooSmall(root)
		local bad = {}
		local checked = 0
		for _, d in root:GetDescendants() do
			if d:IsA("UITextSizeConstraint") then
				local label = d.Parent
				if label and label.Name ~= "KeyCap" then
					checked += 1
					local _, height = refSize(label)
					if d.MaxTextSize < MIN_TEXT then
						table.insert(bad, `{label:GetFullName()} : MaxTextSize {d.MaxTextSize}`)
					elseif height < MIN_TEXT then
						table.insert(bad, `{label:GetFullName()} : boîte de {height} px`)
					end
				end
			end
		end
		return bad, checked
	end

	-- profil riche : perchoirs pleins, réserve, fusions possibles, Atlas débloqué, quêtes du jour
	local function rich()
		local nebbies = {}
		for i = 1, 24 do
			nebbies["u" .. i] = neb((i % 5) + 1)
		end
		nebbies.f1, nebbies.f2, nebbies.f3 = neb(2), neb(2), neb(2)
		nebbies.g1, nebbies.g2, nebbies.g3 = neb(3, 0, 0, 2), neb(3, 0, 0, 2), neb(3, 0, 0, 2, true)
		return {
			glow = 5000,
			stardust = 400,
			idleRate = 120,
			perchIncome = 120,
			nebbies = nebbies,
			atlas = { 255, 255, 3, 0, 0, 0, 0 },
			onboarding = { step = 5, p = 0 },
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
		}
	end

	local function walk(c, label, out)
		frames(c, 4)
		local bad, checked = tooSmall(c.h.localPlayer.PlayerGui.Panels)
		for _, line in bad do
			table.insert(out, `[{label}] {line}`)
		end
		return checked
	end

	describe("Fix restes client-panels › texte ≥ 18 px de référence dans les panneaux (N126, N127)", function()
		for _, lang in { "en", "fr" } do
			it(`tous les panneaux et onglets ({lang}) : aucun texte plafonné sous 18 px`, function()
				local over = rich()
				over.settings = {
					zen = false,
					reducedMotion = false,
					lowGraphics = false,
					music = true,
					sfx = true,
					autoCrew = true,
					refuseInvites = false,
					lang = lang,
				}
				local c = setup(over, function(cc)
					cc.Monetization.Passes.NightShift.id = 777
				end)
				c.h.localPlayer:SetAttribute("Admin", true)
				local bad = {}
				local checked = 0
				local tabs = {
					Upgrades = { false },
					Supernova = { false },
					Collection = { "perches", "stash", "forge", "atlas", "guide" },
					Goals = { "today", "calendar", "week", "welcome" },
					Shop = { "passes", "boosts", "codes" },
					Crew = { false },
					Settings = { false },
				}
				for _, name in { "Upgrades", "Supernova", "Collection", "Goals", "Shop", "Crew", "Settings" } do
					for _, tab in tabs[name] do
						c.PC.open(name, if tab then { tab = tab } else nil)
						expect(c.PC.current()).toBe(name)
						if tab then
							expect(c.PC.currentTab(name)).toBe(tab)
						end
						checked += walk(c, if tab then `{name}/{tab}` else name, bad)
					end
				end
				-- Réserve : un Nebby choisi (barre d'actions remplie)
				c.PC.open("Collection", { tab = "stash" })
				local C = panel(c, "Collection")
				local st = C._state()
				st.grid:scrollTo(1)
				for _, cell in st.grid:cells() do
					if cell.Visible then
						C._tap(cell)
						break
					end
				end
				checked += walk(c, "Collection/stash+focus", bad)
				-- écran de retour (fenêtre compacte)
				panel(c, "ReturnScreen").present({ glow = 125000, seconds = 7200, nightShift = false })
				expect(c.PC.current()).toBe("ReturnScreen")
				frames(c, 20)
				checked += walk(c, "ReturnScreen", bad)
				expect(checked > 150).toBe(true)
				expect(table.concat(bad, "\n")).toBe("")
				expect(#c.h:signalErrors()).toBe(0)
			end)
		end
	end)
end
