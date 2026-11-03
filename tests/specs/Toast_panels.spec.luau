--!nocheck
-- Toast_panels (lot B1, étape 2 ; revue des écrans du 3 novembre, défaut « message par-dessus les
-- onglets » ; GDD v2.0 §10.1 « aucun chevauchement », §10.6 règle 7) : un message (UI/Toast, par la
-- file du HUD comme en jeu, ou montré tout de suite) ne couvre JAMAIS les onglets d'un panneau ouvert,
-- ni son contenu, ni l'élément sous le focus, ni un élément sélectionnable ; dans CHAQUE panneau et
-- CHAQUE onglet de Screens.PANEL_TABS, à tv720, tv1080 et tv2160. Cas couverts : message montré
-- panneau ouvert ; message déjà à l'écran quand le panneau s'ouvre ; onglet changé avec un message à
-- l'écran ; message montré puis panneau fermé (la pile redescend sous les bannières).
-- Zéro trace : aucune erreur ni avertissement du client pendant les scénarios.

local roblox = require("@lune/roblox")
local Screens = require("../harness/Screens")
local Layout = require("../harness/Layout")
local Gamepad = require("../harness/Gamepad")

local Enum = roblox.Enum

local LONG = "Les enclos sont pleins : range ou vends un squishy pour faire de la place !"

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function shown(obj): boolean
		return Layout.visible(obj) and Layout.rect(obj) ~= nil
	end

	-- recouvrement de plus d'un pixel
	local function overlaps(a, b): boolean
		return a.x < b.x + b.w - 1 and b.x < a.x + a.w - 1 and a.y < b.y + b.h - 1 and b.y < a.y + a.h - 1
	end

	local function toasts(c)
		local out = {}
		local playerGui = c.h.localPlayer:FindFirstChildOfClass("PlayerGui")
		local gui = playerGui:FindFirstChild("Toasts")
		local stack = gui and gui:FindFirstChild("Stack", true)
		for _, t in (stack and stack:GetChildren() or {}) do
			if t.Name == "Toast" and shown(t) then
				table.insert(out, t)
			end
		end
		return out
	end

	-- Ce qu'un message ne doit jamais couvrir dans le panneau ouvert : onglets (TvTab), contenu (enfants
	-- du corps), tout objet sélectionnable de la fenêtre, l'objet sous le focus et son cadre
	local function guarded(c, win)
		local out = {}
		if win == nil then
			return out
		end
		local body = win:FindFirstChild("Body")
		for _, part in (body and body:GetChildren() or {}) do
			if part:IsA("GuiObject") and shown(part) then
				table.insert(out, { obj = part, what = "contenu" })
			end
		end
		for _, d in win:GetDescendants() do
			if d:IsA("GuiObject") and shown(d) then
				if d:GetAttribute("TvTab") == true then
					table.insert(out, { obj = d, what = "onglet" })
				elseif d:IsA("GuiButton") and d.Selectable then
					table.insert(out, { obj = d, what = "sélectionnable" })
				end
			end
		end
		local sel = c.h.game.GuiService.SelectedObject
		if sel and shown(sel) then
			table.insert(out, { obj = sel, what = "focus" })
		end
		return out
	end

	local function issues(c, panel: string, label: string, need: boolean): { string }
		Screens.layout(c)
		local win = c.PC.window(panel)
		local list = toasts(c)
		local out = {}
		if need and #list == 0 then
			table.insert(out, label .. " : aucun message à l'écran")
		end
		for _, t in list do
			local r = Layout.rect(t)
			for _, g in guarded(c, win) do
				if overlaps(r, Layout.rect(g.obj)) then
					table.insert(
						out,
						string.format("%s : message sur %s %s", label, g.what, Layout.name(g.obj))
					)
				end
			end
			-- le message reste dans la zone sûre et dans l'écran
			if r.y < -1 or r.y + r.h > c.profile.h + 1 then
				table.insert(out, label .. " : message hors de l'écran")
			end
		end
		return out
	end

	for _, pid in { "tv1080", "tv720", "tv2160" } do
		describe(
			"Toast › un message ne couvre ni les onglets, ni le contenu, ni le focus › " .. pid,
			function()
				local ok, c = pcall(Screens.boot, Harness, Screens.profileById(pid), "fr", "mid")
				if not ok then
					it("démarrage du client", function()
						error(c)
					end)
					return
				end
				local bad = {}
				local function add(list)
					for _, line in list do
						table.insert(bad, line)
					end
				end
				for _, entry in Screens.PANEL_TABS do
					local panel, tabs = entry[1], entry[2]
					for _, tab in tabs do
						local where = panel .. (if tab ~= "" then " › " .. tab else "")
						-- 1. message du jeu (file du HUD) montré panneau ouvert
						Screens.open(c, panel, if tab ~= "" then tab else nil)
						Screens.flushAll(c)
						Screens.layout(c)
						c.Toast.message(LONG, "warning")
						Screens.frames(c, 2, 0.05)
						add(issues(c, panel, where .. " (file, panneau ouvert)", true))
						-- 2. message montré tout de suite (Toast.show d'un panneau)
						c.Toast.show("Rien à ranger", "info")
						Screens.frames(c, 2, 0.05)
						add(issues(c, panel, where .. " (show, panneau ouvert)", true))
						-- 3. message déjà à l'écran quand le panneau s'ouvre
						Screens.closeAll(c)
						Screens.flushAll(c)
						c.Toast.show(LONG, "warning")
						Screens.frames(c, 1, 0.05)
						c.PC.open(panel, if tab ~= "" then tab else nil)
						Screens.frames(c, 3, 0.05)
						add(issues(c, panel, where .. " (déjà là à l'ouverture)", true))
					end
				end
				it(
					"chaque panneau et chaque onglet : message hors des onglets, du contenu et du focus",
					function()
						expect(table.concat(bad, "\n")).toBe("")
					end
				)

				-- les messages les plus longs du jeu (Feedback du serveur, clés feedback.*), fusionnés « ×3 » :
				-- le texte tient dans son message (jamais un débordement sur les onglets)
				local longBad = {}
				local keys = Screens.keysWithPrefix(c, "feedback.")
				table.sort(keys, function(a, b)
					local la = utf8.len(c.Strings.fr[a] or "") or 0
					local lb = utf8.len(c.Strings.fr[b] or "") or 0
					if la ~= lb then
						return la > lb
					end
					return a < b
				end)
				local TextFit = require("../harness/TextFit")
				for i = 1, math.min(4, #keys) do
					local key = keys[i]
					Screens.open(c, "Shop", "passes")
					Screens.flushAll(c)
					for _ = 1, 3 do
						c.h:fireClient(Screens.REMOTES .. "Feedback", {
							key = key,
							vars = Screens.varsFor(c, key),
							tone = "info",
						})
					end
					Screens.frames(c, 3, 0.05)
					for _, line in issues(c, "Shop", "Boutique, " .. key, true) do
						table.insert(longBad, line)
					end
					Screens.layout(c)
					for _, t in toasts(c) do
						local label = t:FindFirstChild("Label")
						local fits, info = TextFit.fits(label)
						if not fits then
							for _, issue in info.issues do
								table.insert(longBad, key .. " : " .. issue.message)
							end
						end
					end
				end
				it(
					"messages les plus longs (×3) dans un panneau : le texte tient, hors des onglets",
					function()
						expect(table.concat(longBad, "\n")).toBe("")
					end
				)

				-- onglet changé (R1) avec un message à l'écran : il reste hors des onglets
				local tabBad = {}
				Screens.open(c, "Ranch", "pens")
				Screens.flushAll(c)
				c.Toast.show(LONG, "warning")
				Screens.frames(c, 2, 0.05)
				for step = 1, 3 do
					c.Clock.advance(0.5)
					Gamepad.tap(c.h, Enum.KeyCode.ButtonR1)
					Screens.frames(c, 2, 0.05)
					for _, line in issues(c, "Ranch", "Ranch › R1 n° " .. step, false) do
						table.insert(tabBad, line)
					end
				end
				it("onglet changé par R1, message à l'écran : jamais sur les onglets", function()
					expect(table.concat(tabBad, "\n")).toBe("")
				end)

				-- panneau fermé, message à l'écran : la pile redescend sous les bannières (place du HUD)
				c.Toast.show(LONG, "warning")
				Screens.frames(c, 2, 0.05)
				Screens.closeAll(c)
				c.Toast.show("Rien à ranger", "info")
				Screens.frames(c, 2, 0.05)
				Screens.layout(c)
				local list = toasts(c)
				local k = Screens.rootScale(c)
				local playerGui = c.h.localPlayer:FindFirstChildOfClass("PlayerGui")
				local safe = playerGui:FindFirstChild("Toasts"):FindFirstChild("Safe")
				local want = Layout.rect(safe).y + (c.Root.padding().Y + c.Messages.TopY) * k
				it("panneau fermé : le message retourne à l'emplacement de message du HUD", function()
					expect(#list >= 1).toBe(true)
					local r = Layout.rect(list[#list])
					-- haut du message à Messages.TopY (emplacement Layout.Hud.message), à 2 px près
					expect({ y = math.floor(r.y + 0.5), near = math.abs(r.y - want) <= 2 }).toEqual({
						y = math.floor(r.y + 0.5),
						near = true,
					})
				end)

				it("zéro trace", function()
					expect(table.concat(c.h.errors, "\n")).toBe("")
					expect(table.concat(c.h:warnings(), "\n")).toBe("")
				end)
				Harness.disposeAll()
			end
		)
	end
end
