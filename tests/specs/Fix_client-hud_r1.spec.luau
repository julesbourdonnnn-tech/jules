--!nocheck
-- QA r1 (paquet client-hud) : texte ≥ 18 px de référence (GDD §10.1). Chaque UITextSizeConstraint
-- du HUD, de la roue de pings, des tampons, bulles et bannières plafonne à 18 px ou plus (seules
-- les touches de raccourci, « KeyCap », restent plus petites) dans une boîte assez haute. Rail :
-- libellé de 22 px (ruban) sous un glyphe 0,7 × 0,5, touche dans le coin haut gauche. Indicateurs
-- d'état : minuteur du boost et « connexion instable » lisibles et sans chevauchement.
local roblox = require("@lune/roblox")
local Vector2 = roblox.Vector2
local Color3 = roblox.Color3

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local T0 = 1800000000
	local MIN_TEXT = 18 -- px de référence (GDD §10.1)
	local EM = 0.5 -- largeur moyenne d'un caractère FredokaOne, en em (estimation prudente)

	local function setup(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", touch = opts.touch })
		h.localPlayer.LocaleId = opts.locale or "en-us"
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
			VFX = h:require(CLIENT .. "Controllers.VFXController"),
			Panels = h:require(CLIENT .. "Controllers.PanelController"),
			FX = h:require(CLIENT .. "UI.ScreenFX"),
			Banners = h:require(CLIENT .. "UI.Banners"),
			Input = h:require(CLIENT .. "Controllers.InputController"),
			HUD = h:require(CLIENT .. "UI.HUD"),
			events = nil,
			open = nil,
		}
		-- isolation : paquets client-world et client-panels remplacés
		c.VFX.playDash = function() end
		c.VFX.playUpgrade = function() end
		c.WSC.localSlot = function()
			return 1
		end
		c.WSC.lineLength = function()
			return 0
		end
		c.WSC.events = function()
			return c.events
		end
		c.Panels.open = function(name)
			c.open = name
		end
		c.Panels.close = function()
			c.open = nil
		end
		c.Panels.current = function()
			return c.open
		end
		c.Root.Init()
		c.State.Init()
		c.Prefs.Init()
		c.Prefs.Start()
		c.FX.Init()
		c.Banners.Init()
		c.Input.Init()
		c.HUD.Init()
		c.FX.Start()
		c.Banners.Start()
		c.Input.Start()
		c.HUD.Start()
		return c
	end

	-- schéma chargé une fois, AVANT les harnais clients (Harness.new redirige les journaux réseau)
	local Schema = Harness.new():require("ServerScriptService.Server.Data.Schema")

	local function snapshot(c, data)
		local profile = Schema.defaults()
		for k, v in data or {} do
			profile[k] = v
		end
		c.h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", profile)
		c.h:settle(1)
	end

	local function hud(c)
		return c.h.localPlayer.PlayerGui.HUD.Safe
	end

	-- rectangle de référence d'un GuiObject dans un parent de pw × ph
	local function rect(gui, pw, ph)
		local w = gui.Size.X.Scale * pw + gui.Size.X.Offset
		local hgt = gui.Size.Y.Scale * ph + gui.Size.Y.Offset
		local x = gui.Position.X.Scale * pw + gui.Position.X.Offset - gui.AnchorPoint.X * w
		local y = gui.Position.Y.Scale * ph + gui.Position.Y.Offset - gui.AnchorPoint.Y * hgt
		return { x0 = x, y0 = y, x1 = x + w, y1 = y + hgt, w = w, h = hgt }
	end

	local function overlaps(a, b)
		return a.x0 < b.x1 and b.x0 < a.x1 and a.y0 < b.y1 and b.y0 < a.y1
	end

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

	-- largeur estimée d'un texte d'une ligne à `size` px
	local function textWidth(text, size)
		return (utf8.len(text) or #text) * EM * size
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

	describe("QA r1 client-hud › texte ≥ 18 px de référence (GDD §10.1)", function()
		it("HUD, roue de pings, tampons, bulles et bannières : aucun texte plafonné sous 18 px", function()
			local c = setup()
			snapshot(c, { boosts = { personalUntil = T0 + 90 } })
			c.HUD.revealAll()
			c.h.localPlayer:SetAttribute("Unstable", true)
			c.Input.openPingWheel()
			c.FX.stamp("CATCH!", Color3.new(1, 1, 1))
			c.FX.stamp("+1", Color3.new(1, 1, 1), "small")
			c.FX.floater("+120", Vector2.new(640, 360), Color3.new(1, 1, 1))
			c.Banners.show({ kind = "megaParade", args = { userId = 7, name = "Mira", n = 32 }, priority = 4 })
			c.h:settle(1)
			c.h:step(1 / 30, 10)
			local bad, checked = tooSmall(c.h.localPlayer.PlayerGui)
			expect(checked > 40).toBe(true)
			expect(table.concat(bad, "\n")).toBe("")
			-- seules les touches de raccourci restent plus petites (petites capsules de 26 × 22)
			local caps = 0
			for _, d in c.h.localPlayer.PlayerGui:GetDescendants() do
				if d.Name == "KeyCap" and d:IsA("TextLabel") then
					caps += 1
					expect(d.Size.Y.Offset <= 22).toBe(true)
				end
			end
			expect(caps > 0).toBe(true)
			expect(#c.h:signalErrors()).toBe(0)
		end)

		it(
			"rail : ruban de 22 px sous un glyphe 0,7 × 0,5 ; touche en haut ; « Collection » tient à 18 px",
			function()
				local c = setup()
				for _, name in { "Upgrades", "Collection", "Goals", "Shop" } do
					local button = hud(c).Rail[name].Button
					local size = button.Parent.Size
					local bw, bh = size.X.Offset, size.Y.Offset
					expect(bw).toBe(80)
					local glyph = rect(button.Icon, bw, bh)
					local label = button.Label
					local box = rect(label, bw, bh)
					expect(math.abs(button.Icon.Size.X.Scale - 0.7) < 1e-4).toBe(true)
					expect(math.abs(button.Icon.Size.Y.Scale - 0.5) < 1e-4).toBe(true)
					expect(box.h >= 20 and box.h <= 22).toBe(true)
					expect(label:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize >= MIN_TEXT).toBe(
						true
					)
					-- le glyphe finit au-dessus du ruban, le ruban reste dans la hauteur du bouton
					expect(glyph.y1 <= box.y0).toBe(true)
					expect(box.y0 >= 0 and box.y1 <= bh).toBe(true)
					-- ruban lisible sur le monde : fond sombre arrondi
					expect(label.BackgroundTransparency < 1).toBe(true)
					expect(label:FindFirstChildOfClass("UICorner") ~= nil).toBe(true)
					-- la touche (PC) ne masque plus le début du libellé
					expect(overlaps(rect(button.KeyCap, bw, bh), box)).toBe(false)
					-- le débord du ruban reste dans la marge de 16 px du bord d'écran
					expect(box.x0 >= -8).toBe(true)
				end
				-- anglais et français : le libellé le plus long tient en une ligne à 18 px
				local width = rect(hud(c).Rail.Collection.Button.Label, 80, 80).w
				for _, lang in { "en", "fr" } do
					for _, key in
						{ "hud.rail.upgrades", "hud.rail.collection", "hud.rail.goals", "hud.rail.shop" }
					do
						local text = c.L.get(lang, key)
						expect(textWidth(text, MIN_TEXT) <= width).toBe(true)
					end
				end
			end
		)

		it("roue de pings : libellés ≥ 18 px sous le glyphe, touche hors du libellé", function()
			local c = setup()
			c.Input.openPingWheel()
			local wheel = c.h.localPlayer.PlayerGui.PingWheel.Safe.Wheel
			for i = 1, 6 do
				local button = wheel["Sector" .. i].Button
				local size = button.Parent.Size
				local bw, bh = size.X.Offset, size.Y.Offset
				local box = rect(button.Label, bw, bh)
				expect(button.Label:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize >= MIN_TEXT).toBe(
					true
				)
				expect(box.h >= MIN_TEXT).toBe(true)
				expect(rect(button.Icon, bw, bh).y1 <= box.y0).toBe(true)
				expect(overlaps(rect(button.KeyCap, bw, bh), box)).toBe(false)
				for _, lang in { "en", "fr" } do
					expect(textWidth(c.L.get(lang, "ping." .. i), MIN_TEXT) <= box.w).toBe(true)
				end
			end
		end)

		it("état : minuteur du boost et « connexion instable » ≥ 18 px, sans chevauchement", function()
			local c = setup()
			snapshot(c, { boosts = { personalUntil = T0 + 1200 } })
			c.HUD.reveal("status", false)
			local player = c.h.localPlayer
			player:SetAttribute("Unstable", true)
			c.h:settle(1)
			c.h:step(1 / 30, 7)
			local status = hud(c).Status
			local W, H = status.Size.X.Offset, status.Size.Y.Offset
			local time = status.Row.Boost.Time
			local caption = status.Caption
			expect(time.Text).toBe("20:00")
			expect(time:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize >= MIN_TEXT).toBe(true)
			expect(caption:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize >= MIN_TEXT).toBe(true)
			expect(caption.Visible).toBe(true)

			-- icônes visibles alignées à droite (UIListLayout, écart 8) : on recalcule leurs places
			local function icons()
				local order = { "Rookie", "Zen", "Boost", "Unstable" }
				local shown = {}
				for _, name in order do
					if status.Row[name].Visible then
						table.insert(shown, name)
					end
				end
				local out = {}
				local x = W
				for i = #shown, 1, -1 do
					x -= 48
					out[shown[i]] = { x0 = x, y0 = 0, x1 = x + 48, y1 = 48 }
					x -= 8
				end
				return out, #shown
			end

			local function check()
				local placed, n = icons()
				local cap = rect(caption, W, H)
				expect(cap.h >= MIN_TEXT).toBe(true)
				-- la légende se place à gauche des icônes visibles, centrée sur la rangée
				expect(cap.x1 <= W - (n * 48 + (n - 1) * 8)).toBe(true)
				expect(cap.y0 >= 0 and cap.y1 <= 48).toBe(true)
				for _, r in placed do
					expect(overlaps(cap, r)).toBe(false)
				end
				local boost = placed.Boost
				if boost then
					local t = rect(time, 48, 48)
					local timeBox = { x0 = boost.x0 + t.x0, y0 = t.y0, x1 = boost.x0 + t.x1, y1 = t.y1 }
					expect(timeBox.y1 - timeBox.y0 >= MIN_TEXT).toBe(true)
					expect(overlaps(cap, timeBox)).toBe(false)
					-- le minuteur reste au-dessus du suivi de quête (STATUS + 30 sous la rangée)
					expect(timeBox.y1 <= 48 + 30).toBe(true)
					expect(textWidth(time.Text, MIN_TEXT) <= timeBox.x1 - timeBox.x0).toBe(true)
				end
				for _, lang in { "en", "fr" } do
					expect(textWidth(c.L.get(lang, "hud.unstable"), MIN_TEXT) <= cap.w).toBe(true)
				end
			end

			check() -- boost + instable
			player:SetAttribute("Rookie", true)
			c.Prefs._onSettings({ zen = true })
			c.h:settle(1)
			c.h:step(1 / 30, 7)
			expect(status.Row.Zen.Visible).toBe(true)
			check() -- les quatre icônes : la légende glisse vers la gauche
			c.Clock.advance(1300)
			player:SetAttribute("Rookie", false)
			c.Prefs._onSettings({ zen = false, lang = "fr" })
			c.h:settle(1)
			c.h:step(1 / 30, 7)
			expect(status.Row.Boost.Visible).toBe(false)
			expect(caption.Text).toBe(c.L.get("fr", "hud.unstable"))
			check() -- instable seul, en français
			player:SetAttribute("Unstable", false)
			c.h:step(1 / 30, 7)
			expect(caption.Visible).toBe(false)
		end)

		it("réapparition : le HUD survit (ResetOnSpawn = false) avec ses tailles de texte", function()
			local c = setup()
			local label = hud(c).Rail.Upgrades.Button.Label
			c.h:respawn(c.h.localPlayer)
			c.h:settle(2)
			expect(hud(c).Rail.Upgrades.Button.Label).toBe(label)
			expect(label:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize >= MIN_TEXT).toBe(true)
		end)
	end)
end
