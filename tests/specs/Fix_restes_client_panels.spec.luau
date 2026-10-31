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
local Vector2 = roblox.Vector2

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

		it(
			"moins de Nebbies que de perchoirs : « 0/300 », jamais négatif ; Stash Plus → /600",
			function()
				local c = setup({
					nebbies = many(2),
					upgrades = { conga = 0, stride = 0, lure = 0, perches = 27, guard = 0 },
					passes = { StashPlus = true },
				})
				c.PC.open("Collection", { tab = "stash" })
				local count = c.PC.page("Collection").Body.Tab_stash.Toolbar.Count
				expect(count.Text).toBe("0/600")
			end
		)
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

	describe(
		"Fix restes client-panels › texte ≥ 18 px de référence dans les panneaux (N126, N127)",
		function()
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
					for _, name in
						{ "Upgrades", "Supernova", "Collection", "Goals", "Shop", "Crew", "Settings" }
					do
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
		end
	)

	-- ==========================================================================================
	-- Variante téléphone, plus stricte : taille réelle de la zone sûre du ScreenGui, échelle 0,6
	-- (Root : clamp(min(l / 1280, h / 720), 0,6, 1,25)), UISizeConstraint (fenêtre plafonnée),
	-- UIPadding des parents et cellules d'UIGridLayout pris en compte
	-- ==========================================================================================
	local strictContent

	local function pad(u, total)
		if u == nil then
			return 0
		end
		return u.Scale * total + u.Offset
	end

	local function strictOwn(gui, root)
		if gui == nil or gui:IsA("PlayerGui") or gui:IsA("ScreenGui") then
			return root.X, root.Y
		end
		local parent = gui.Parent
		local pw, ph = strictContent(parent, root)
		if not gui:IsA("GuiObject") then
			return pw, ph
		end
		local grid = parent and parent:FindFirstChildOfClass("UIGridLayout")
		local size = if grid then grid.CellSize else gui.Size
		local w = size.X.Scale * pw + size.X.Offset
		local hgt = size.Y.Scale * ph + size.Y.Offset
		local constraint = gui:FindFirstChildOfClass("UISizeConstraint")
		if constraint then
			local lo, hi = constraint.MinSize, constraint.MaxSize
			w = math.max(lo.X, math.min(hi.X, w))
			hgt = math.max(lo.Y, math.min(hi.Y, hgt))
		end
		return w, hgt
	end

	strictContent = function(gui, root)
		local w, hgt = strictOwn(gui, root)
		local p = gui and gui:FindFirstChildOfClass("UIPadding")
		if p then
			w -= pad(p.PaddingLeft, w) + pad(p.PaddingRight, w)
			hgt -= pad(p.PaddingTop, hgt) + pad(p.PaddingBottom, hgt)
		end
		return w, hgt
	end

	local function tooSmallStrict(rootGui, root, skip)
		local bad = {}
		local checked = 0
		for _, d in rootGui:GetDescendants() do
			if d:IsA("UITextSizeConstraint") then
				local label = d.Parent
				local name = label and label:GetFullName() or ""
				local skipped = false
				for _, pattern in skip or {} do
					if string.find(name, pattern, 1, true) then
						skipped = true
					end
				end
				if label and label.Name ~= "KeyCap" and not skipped then
					checked += 1
					local _, height = strictOwn(label, root)
					if d.MaxTextSize < MIN_TEXT then
						table.insert(bad, `{name} : MaxTextSize {d.MaxTextSize}`)
					elseif height < MIN_TEXT - 1e-6 then
						table.insert(bad, `{name} : boîte de {math.floor(height * 10) / 10} px`)
					end
				end
			end
		end
		return bad, checked
	end

	describe("Fix restes client-panels › téléphones (zone sûre réelle, échelle 0,6)", function()
		-- zone sûre du ScreenGui (sans encoche, barre Roblox ni barre d'accueil) ; caméra = écran entier
		local PHONES = {
			{ name = "iPhone SE", viewport = Vector2.new(568, 320), safe = Vector2.new(568, 284) },
			{ name = "iPhone 12", viewport = Vector2.new(844, 390), safe = Vector2.new(750, 333) },
		}
		-- panneaux de ce correctif seulement (Upgrades, Supernova, Crew : autres paquets)
		for _, phone in PHONES do
			it(`{phone.name} : Collection, Objectifs, Boutique, Réglages, retour ≥ 18 px`, function()
				local c = setup(rich(), function(cc)
					cc.h.workspace.CurrentCamera.ViewportSize = phone.viewport
					cc.Monetization.Passes.NightShift.id = 777
				end)
				expect(c.Root.scale()).toBe(0.6)
				c.h.localPlayer:SetAttribute("Admin", true)
				local tabs = {
					Collection = { "perches", "stash", "forge", "atlas", "guide" },
					Goals = { "today", "calendar", "week", "welcome" },
					Shop = { "passes", "boosts", "codes" },
					Settings = { false },
				}
				local bad = {}
				local checked = 0
				-- chaque page est mesurée juste après son ouverture : la fenêtre partagée change de
				-- taille (compacte pour l'écran de retour)
				local function measure(name, label)
					local found, n = tooSmallStrict(c.PC.page(name), phone.safe)
					checked += n
					for _, line in found do
						table.insert(bad, `[{label}] {line}`)
					end
				end
				for _, name in { "Collection", "Goals", "Shop", "Settings" } do
					for _, tab in tabs[name] do
						c.PC.open(name, if tab then { tab = tab } else nil)
						frames(c, 4)
						measure(name, if tab then `{name}/{tab}` else name)
					end
				end
				panel(c, "ReturnScreen").present({ glow = 125000, seconds = 7200, nightShift = false })
				frames(c, 20)
				expect(c.PC.current()).toBe("ReturnScreen")
				measure("ReturnScreen", "ReturnScreen")
				expect(checked > 300).toBe(true)
				expect(table.concat(bad, "\n")).toBe("")
			end)
		end
	end)

	-- ==========================================================================================
	-- Écran de retour : la ligne Night Shift (18 px) ne chevauche ni le bouton ni le montant
	-- ==========================================================================================
	describe("Fix restes client-panels › écran de retour sans chevauchement", function()
		local function rect(gui, pw, ph)
			local w = gui.Size.X.Scale * pw + gui.Size.X.Offset
			local hgt = gui.Size.Y.Scale * ph + gui.Size.Y.Offset
			local x = gui.Position.X.Scale * pw + gui.Position.X.Offset - gui.AnchorPoint.X * w
			local y = gui.Position.Y.Scale * ph + gui.Position.Y.Offset - gui.AnchorPoint.Y * hgt
			return { x0 = x, y0 = y, x1 = x + w, y1 = y + hgt, w = w, h = hgt }
		end

		it("titre, montant, Night Shift et bouton empilés sans recouvrement (PC et téléphones)", function()
			local c = setup({}, function(cc)
				cc.Monetization.Passes.NightShift.id = 777
			end)
			panel(c, "ReturnScreen").present({ glow = 5000, seconds = 600 })
			local body = c.PC.page("ReturnScreen").Body
			expect(body.NightShift.Visible).toBe(true)
			expect(body.NightShift:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize >= MIN_TEXT).toBe(
				true
			)
			expect(body.Ok.Size.Y.Offset).toBe(96)
			-- corps de la fenêtre compacte : 1280 × 720 (≈ 344 px), iPhone 12 (≈ 238), iPhone SE (≈ 204,
			-- fenêtre au minimum 420 × 300 de PanelController)
			for _, size in { { 596, 344 }, { 589, 238 }, { 437, 204 } } do
				local pw, ph = size[1], size[2]
				local title = rect(body.Title, pw, ph)
				local amount = rect(body.Amount, pw, ph)
				local night = rect(body.NightShift, pw, ph)
				local ok = rect(body.Ok, pw, ph)
				expect(night.h >= MIN_TEXT).toBe(true)
				expect(night.y1 <= ok.y0).toBe(true)
				expect(amount.y1 <= night.y0).toBe(true)
				expect(title.y1 <= amount.y0).toBe(true)
				expect(amount.h >= 18).toBe(true)
				expect(ok.y1 <= ph).toBe(true)
			end
		end)
	end)

	-- ==========================================================================================
	-- Q19 : « Ton Nid travaille même quand tu dors » + plafond hors ligne dans le menu (GDD §7.1)
	-- ==========================================================================================
	describe("Fix restes client-panels › pied d'information des Réglages (Q19)", function()
		local NBSP = "\u{A0}"

		local function settings(lang)
			return {
				zen = false,
				reducedMotion = false,
				lowGraphics = false,
				music = true,
				sfx = true,
				autoCrew = true,
				refuseInvites = false,
				lang = lang,
			}
		end

		it("anglais : Nid hors ligne, 50 % pendant 8 h ; Night Shift → 75 % pendant 12 h", function()
			local c = setup({ settings = settings("en") })
			c.PC.open("Settings")
			local S = panel(c, "Settings")
			local nest, offline = S._info()
			expect(nest.Text).toBe("🌙 Your Nest works even while you sleep")
			expect(offline.Text).toBe("Offline: 50% of your perches' Glow, for up to 8h")
			-- dernier élément de la liste, toujours visible (pas réservé aux admins)
			local info = nest.Parent
			local list = info.Parent
			local last = 0
			for _, child in list:GetChildren() do
				if child:IsA("GuiObject") and child ~= info then
					last = math.max(last, child.LayoutOrder)
				end
			end
			expect(info.LayoutOrder > last).toBe(true)
			expect(info.Visible).toBe(true)
			expect(nest:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize >= MIN_TEXT).toBe(true)
			expect(offline:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize >= MIN_TEXT).toBe(true)
			patch(c, { passes = { NightShift = true } })
			frames(c, 2)
			expect(offline.Text).toBe("Offline: 75% of your perches' Glow, for up to 12h")
		end)

		it("français : textes traduits, espaces insécables de Prefs.duration", function()
			local c = setup({ settings = settings("fr") })
			c.PC.open("Settings")
			local nest, offline = panel(c, "Settings")._info()
			expect(nest.Text).toBe("🌙 Ton Nid travaille même quand tu dors")
			expect(offline.Text).toBe("Hors ligne : 50 % du Glow de tes perchoirs, jusqu'à 8" .. NBSP .. "h")
			patch(c, { passes = { NightShift = true } })
			frames(c, 2)
			expect(offline.Text).toBe(
				"Hors ligne : 75 % du Glow de tes perchoirs, jusqu'à 12" .. NBSP .. "h"
			)
		end)

		it("changement de langue en direct : le pied suit", function()
			local c = setup({ settings = settings("en") })
			c.PC.open("Settings")
			local nest, offline = panel(c, "Settings")._info()
			expect(nest.Text).toBe("🌙 Your Nest works even while you sleep")
			patch(c, { settings = settings("fr") })
			frames(c, 2)
			expect(nest.Text).toBe("🌙 " .. c.L.get("fr", "onboarding.nestWorks"))
			expect(string.find(offline.Text, "Hors ligne", 1, true) ~= nil).toBe(true)
			-- chaque clé existe dans les deux langues (pas de repli silencieux sur l'anglais)
			for _, key in { "onboarding.nestWorks", "settings.offlineCap", "settings.zenBankFirst" } do
				expect(c.L.get("en", key) ~= key).toBe(true)
				expect(c.L.get("fr", key) ~= key).toBe(true)
				expect(c.L.get("fr", key) ~= c.L.get("en", key)).toBe(true)
			end
		end)
	end)

	-- ==========================================================================================
	-- N77 : quitter le Mode Zen avec une file non vide (miroir de NestService)
	-- ==========================================================================================
	describe("Fix restes client-panels › Mode Zen : faire parader la file d'abord (N77)", function()
		local function zenSettings(zen, lang)
			return {
				zen = zen,
				reducedMotion = false,
				lowGraphics = false,
				music = true,
				sfx = true,
				autoCrew = true,
				refuseInvites = false,
				lang = lang or "en",
			}
		end

		local function zenSetup(zen, lang)
			local c = setup({ settings = zenSettings(zen, lang) })
			c.line = 0
			c.WSC.lineLength = function(slot)
				return if slot == 1 then c.line else 0
			end
			goHome(c, 1)
			c.PC.open("Settings")
			c.S = panel(c, "Settings")
			frames(c, 12)
			return c
		end

		it("Zen actif + file de 4 : interrupteur désactivé, ligne d'état, rien d'envoyé", function()
			local c = zenSetup(true)
			local row = c.S._rows.zen
			c.line = 4
			frames(c, 12)
			expect(row.status.Text).toBe("Parade your line first to leave Calm Mode")
			expect(row.toggle:GetAttribute("Disabled")).toBe(true)
			expect(row.toggle:GetAttribute("On")).toBe(true)
			click(row.toggle)
			c.S.setSetting("zen", false)
			frames(c, 2)
			expect(#sent(c, "SetSetting")).toBe(0)
			expect(row.toggle:GetAttribute("On")).toBe(true) -- aucun basculement optimiste
			-- la file a paradé : l'interrupteur se libère, Zen OFF part
			c.line = 0
			frames(c, 12)
			expect(row.status.Text).toBe("")
			expect(row.toggle:GetAttribute("Disabled")).toBe(false)
			click(row.toggle)
			local sets = sent(c, "SetSetting")
			expect(#sets).toBe(1)
			expect(sets[1][1]).toBe("zen")
			expect(sets[1][2]).toBe(false)
		end)

		it(
			"Zen inactif avec une file : l'activer reste possible (la règle ne vise que la sortie)",
			function()
				local c = zenSetup(false)
				c.line = 6
				frames(c, 12)
				local row = c.S._rows.zen
				expect(row.status.Text).toBe("")
				click(row.toggle)
				local sets = sent(c, "SetSetting")
				expect(#sets).toBe(1)
				expect(sets[1][2]).toBe(true)
			end
		)

		it("hors du port sûr : le message du port reste prioritaire (même ordre que le serveur)", function()
			local c = zenSetup(true)
			c.line = 3
			local me = c.h.localPlayer
			me.Character.HumanoidRootPart.CFrame = CFrame.new(0, 3, 30)
			frames(c, 12)
			expect(c.S._rows.zen.status.Text).toBe("Only in your Nest's safe harbor")
		end)

		it("français : « Fais d'abord parader ta file pour quitter le Mode Zen »", function()
			local c = zenSetup(true, "fr")
			c.line = 2
			frames(c, 12)
			expect(c.S._rows.zen.status.Text).toBe("Fais d'abord parader ta file pour quitter le Mode Zen")
			expect(c.S._rows.zen.status:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize >= MIN_TEXT).toBe(
				true
			)
		end)
	end)
end
