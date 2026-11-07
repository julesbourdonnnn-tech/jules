--!nocheck
-- Text_icons (lot B1, étape 2 ; règle 18 du GDD v2.0 §10.8 « aucun symbole hors police », INT-V2-GLYPHS a,
-- docs/04 §27.11) : « ★ » de common.stars et celebrate.star devient une étoile DESSINÉE (UI/Glyph.star) :
--   * aucune clé ne contient plus « ★ » ; le repère « {*} » (UI/Text.STAR) n'est jamais montré tel quel :
--     le texte porte des espaces ordinaires de la largeur de l'étoile, l'étoile est un enfant du
--     libellé, posée après « 3 » (ou avant, « {*}3 ! »), dans la boîte, à la couleur du texte ;
--   * l'étoile est un pentagramme de 5 traits et un disque (aucune image), liseré sombre dessous ;
--   * changement de langue, de couleur, de taille, puis texte sans repère : étoile suivie puis retirée ;
--   * dans le vrai client (Ranch › Enclos à 5 étoiles, carte de la cible du HUD, texte flottant d'une
--     fusion) : aucun texte affiché ne contient « {*} » ni « ★ ».
-- Zéro trace : aucune erreur ni avertissement.

local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Screens = require("../harness/Screens")
local Layout = require("../harness/Layout")

local UDim2 = roblox.UDim2
local Color3 = roblox.Color3
local Enum = roblox.Enum

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function label(c, xAlign)
		local safe = c.Root.safe("IconTest", 20)
		local l = c.h.globals.Instance.new("TextLabel")
		l.Name = "L"
		l.Size = UDim2.fromOffset(400, 60)
		l.Position = UDim2.fromOffset(100, 100)
		l.FontFace = c.Theme.Fonts.Body
		l.TextColor3 = c.Theme.Colors.Gold
		l.TextXAlignment = xAlign or Enum.TextXAlignment.Left
		l.Parent = safe
		c.Text.style(l, "label", 32)
		Layout.apply(c.h)
		return l
	end

	local function setup()
		local h = TvAudit.client({ lang = "fr" })
		return {
			h = h,
			Text = TvAudit.mod(h, "UI.Text"),
			Glyph = TvAudit.mod(h, "UI.Glyph"),
			Theme = TvAudit.mod(h, "UI.Theme"),
			Root = TvAudit.mod(h, "UI.Root"),
			Prefs = TvAudit.mod(h, "Util.Prefs"),
			Strings = h:require("ReplicatedStorage.Shared.Localization.Strings"),
		}
	end

	local function clean(c)
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	describe("Text_icons › étoile dessinée à la place de « ★ »", function()
		it(
			"aucune clé EN ni FR ne contient « ★ » dans common.stars et celebrate.star ; repère {*}",
			function()
				local c = setup()
				for _, lang in { "en", "fr" } do
					for _, key in { "common.stars", "celebrate.star" } do
						local text = c.Strings[lang][key]
						expect({ lang = lang, key = key, star = string.find(text, "★", 1, true) ~= nil }).toEqual({
							lang = lang,
							key = key,
							star = false,
						})
						expect(string.find(text, c.Text.STAR, 1, true) ~= nil).toBe(true)
					end
				end
				clean(c)
			end
		)

		it(
			"« 3 » puis l'étoile : espaces dans le texte, étoile dessinée après le chiffre, dans la boîte",
			function()
				local c = setup()
				local l = label(c)
				c.Text.set(l, "common.stars", { n = 3 })
				Layout.apply(c.h)
				expect(string.find(l.Text, "{*}", 1, true)).toBeNil()
				expect(string.find(l.Text, "★", 1, true)).toBeNil()
				expect(string.sub(l.Text, 1, 1)).toBe("3")
				expect(string.match(l.Text, "^3 +$") ~= nil).toBe(true)
				local icons = c.Text.icons(l)
				expect(#icons).toBe(1)
				local star = icons[1]
				expect(star.Parent).toBe(l)
				expect(star:GetAttribute("Icon")).toBe("star")
				-- aligné à gauche : centre de l'étoile après la largeur de « 3 », dans la boîte du libellé
				expect(star.Position.X.Offset > 10).toBe(true)
				expect(star.Position.X.Offset < 80).toBe(true)
				expect(math.abs(star.Position.Y.Offset - 30) < 1).toBe(true)
				local r, lr = Layout.rect(star), Layout.rect(l)
				expect(r.x >= lr.x and r.y >= lr.y and r.x + r.w <= lr.x + lr.w and r.y + r.h <= lr.y + lr.h).toBe(
					true
				)
				-- pentagramme de 5 traits et un disque, couleur du texte dessus, liseré dessous
				local fill, edge = star:FindFirstChild("Fill"), star:FindFirstChild("Edge")
				expect(#fill:GetChildren()).toBe(6)
				expect(#edge:GetChildren()).toBe(6)
				expect(fill.Ray1.BackgroundColor3).toBe(c.Theme.Colors.Gold)
				expect(fill.ZIndex > edge.ZIndex).toBe(true)
				for _, part in star:GetDescendants() do
					expect(part.ClassName == "ImageLabel" or part.ClassName == "TextLabel").toBe(false)
				end
				clean(c)
			end
		)

		it(
			"« 3{*} ! » (fusion, texte flottant) : l'étoile après le chiffre, jamais en tête de ligne ; centré",
			function()
				local c = setup()
				-- jamais de repère en tête : des espaces de début de ligne peuvent être mangés par une coupure
				for _, lang in { "en", "fr" } do
					expect(string.sub(c.Strings[lang]["celebrate.star"], 1, 3) ~= c.Text.STAR).toBe(true)
				end
				local l = label(c, Enum.TextXAlignment.Center)
				c.Text.set(l, "celebrate.star", { n = 3 })
				Layout.apply(c.h)
				expect(string.match(l.Text, "^3 + !$") ~= nil).toBe(true)
				local star = c.Text.icons(l)[1]
				-- centré dans 400 px : l'étoile juste après le milieu
				expect(star.Position.X.Offset > 190 and star.Position.X.Offset < 260).toBe(true)
				clean(c)
			end
		)

		it(
			"phrase longue (carte de la cible) : l'étoile suit sa place, couleur et langue suivies, retirée sans repère",
			function()
				local c = setup()
				local l = label(c)
				c.Text.raw(l, "Doré · 5" .. c.Text.STAR .. " · Taille 1,2 M")
				Layout.apply(c.h)
				local star = c.Text.icons(l)[1]
				local x1 = star.Position.X.Offset
				expect(x1 > 60).toBe(true)
				-- couleur du texte changée (case choisie) : étoile repeinte
				l.TextColor3 = Color3.fromRGB(16, 12, 30)
				expect(star.Fill.Ray3.BackgroundColor3).toBe(Color3.fromRGB(16, 12, 30))
				-- langue changée : retraduite, toujours une étoile
				c.Text.set(l, "common.stars", { n = 2 })
				c.Prefs._onSettings({ lang = "en" })
				c.h:settle(2)
				expect(#c.Text.icons(l)).toBe(1)
				expect(string.find(l.Text, "{*}", 1, true)).toBeNil()
				-- texte sans repère : étoile retirée
				c.Text.raw(l, "Taille 1,2 M")
				expect(#c.Text.icons(l)).toBe(0)
				expect(l:FindFirstChild("TextIcon1")).toBeNil()
				clean(c)
			end
		)

		-- lot B4, étape 5 (D16, D20, INT-B1-GLYPHS2) : « ♛ » du panneau des ranchs (hors des polices) devient
		-- une couronne DESSINÉE (repère Text.CROWN), la goutte du halo une goutte dessinée (Text.DROP)
		it(
			"couronne « {^} » : jamais montrée telle quelle, dessinée, suit couleur, taille, texte et langue",
			function()
				local c = setup()
				local l = label(c)
				c.Text.raw(l, "Mira · " .. c.Text.CROWN .. "2 · Jour 42")
				Layout.apply(c.h)
				expect(string.find(l.Text, "{^}", 1, true)).toBeNil()
				expect(string.find(l.Text, "♛", 1, true)).toBeNil()
				expect(string.match(l.Text, "^Mira · +2 · Jour 42$") ~= nil).toBe(true)
				local icons = c.Text.icons(l)
				expect(#icons).toBe(1)
				local crown = icons[1]
				expect(crown:GetAttribute("Icon")).toBe("crown")
				expect(crown.Parent).toBe(l)
				-- 5 primitives (bandeau, corps, 3 pointes), liseré sombre dessous, couleur du texte dessus
				expect(#crown.Fill:GetChildren()).toBe(5)
				expect(#crown.Edge:GetChildren()).toBe(5)
				expect(crown.Fill.Band.BackgroundColor3).toBe(c.Theme.Colors.Gold)
				expect(crown.Fill.ZIndex > crown.Edge.ZIndex).toBe(true)
				for _, part in crown:GetDescendants() do
					expect(part.ClassName == "ImageLabel" or part.ClassName == "TextLabel").toBe(false)
				end
				-- après « Mira · » (aligné à gauche), dans la boîte
				local x1 = crown.Position.X.Offset
				expect(x1 > 40 and x1 < 160).toBe(true)
				local r, lr = Layout.rect(crown), Layout.rect(l)
				expect(r.x >= lr.x and r.y >= lr.y and r.x + r.w <= lr.x + lr.w and r.y + r.h <= lr.y + lr.h).toBe(
					true
				)
				-- couleur du texte changée : couronne repeinte
				l.TextColor3 = Color3.fromRGB(16, 12, 30)
				expect(crown.Fill.TipC.BackgroundColor3).toBe(Color3.fromRGB(16, 12, 30))
				-- taille changée : couronne agrandie
				local size = crown.Size.X.Offset
				-- (le panneau est réécrit par RanchRenderer : l'icône est replacée à la nouvelle taille)
				c.Text.style(l, "label", 48)
				c.h:settle(1)
				c.Text.raw(l, "Mira · " .. c.Text.CROWN .. "2 · Jour 42")
				Layout.apply(c.h)
				expect(c.Text.icons(l)[1].Size.X.Offset > size).toBe(true)
				-- autre langue (panneau réécrit par RanchRenderer) : toujours une couronne, plus loin (nom plus long)
				c.Text.style(l, "label", 32)
				c.h:settle(1)
				c.Text.raw(l, "Maximilian · " .. c.Text.CROWN .. "400 · Day 9999")
				Layout.apply(c.h)
				expect(#c.Text.icons(l)).toBe(1)
				expect(c.Text.icons(l)[1].Position.X.Offset > x1).toBe(true)
				-- étoile puis couronne à la même place : l'icône est redessinée dans la bonne forme
				c.Text.raw(l, "5" .. c.Text.STAR)
				expect(c.Text.icons(l)[1]:GetAttribute("Icon")).toBe("star")
				c.Text.raw(l, "5" .. c.Text.CROWN)
				expect(c.Text.icons(l)[1]:GetAttribute("Icon")).toBe("crown")
				expect(#c.Text.icons(l)).toBe(1)
				-- goutte du halo : 2 primitives, attribut Icon « drop »
				c.Text.raw(l, "Sky Keeper · " .. c.Text.DROP .. "60")
				local drop = c.Text.icons(l)[1]
				expect(drop:GetAttribute("Icon")).toBe("drop")
				expect(#drop.Fill:GetChildren()).toBe(2)
				expect(string.find(l.Text, "{~}", 1, true)).toBeNil()
				-- les trois repères dans un texte : trois icônes, chacune la sienne
				c.Text.raw(l, c.Text.CROWN .. "1 " .. c.Text.STAR .. "2 " .. c.Text.DROP .. "3")
				local kinds = {}
				for _, icon in c.Text.icons(l) do
					table.insert(kinds, icon:GetAttribute("Icon"))
				end
				expect(kinds).toEqual({ "crown", "star", "drop" })
				-- texte sans repère : plus aucune icône
				c.Text.raw(l, "Mira")
				expect(#c.Text.icons(l)).toBe(0)
				clean(c)
			end
		)

		-- lot B4, étape 5 (captures du groupe « world ») : la couronne et son liseré remplissaient toute la
		-- place réservée (5 espaces de Fredoka One, 1,05 de la taille du texte, pour un dessin de 1,01) :
		-- elle touchait le chiffre qui la suit (« ♛400 » du panneau des ranchs). Liseré compris, couronne
		-- et goutte laissent au moins 0,1 de la taille du texte d'air de chaque côté, dans les deux polices
		-- du thème (Fredoka One, Luckiest Guy).
		it(
			"couronne et goutte : le dessin, liseré compris, laisse de l'air avant et après (≥ 0,1 de la taille)",
			function()
				local c = setup()
				local TextService = c.h.game:GetService("TextService")
				local function width(text, size, font)
					return TextService:GetTextSize(text, size, font, roblox.Vector2.new(1e5, 1e5)).X
				end
				-- étendue horizontale du liseré (la couche la plus large) autour du centre de l'icône :
				-- rectangles arrondis tournés (pointes de la couronne et de la goutte à 45°)
				local function extent(icon)
					local s = icon.Size.X.Offset
					local lo, hi = math.huge, -math.huge
					for _, part in icon.Edge:GetChildren() do
						local a, b = part.Size.X.Scale * s, part.Size.Y.Scale * s
						local corner = part:FindFirstChildOfClass("UICorner")
						local rho = if corner then corner.CornerRadius.Scale * math.min(a, b) else 0
						local t = math.rad(part.Rotation)
						local half = (a / 2 - rho) * math.abs(math.cos(t))
							+ (b / 2 - rho) * math.abs(math.sin(t))
							+ rho
						local cx = (part.Position.X.Scale - 0.5) * s
						lo = math.min(lo, cx - half)
						hi = math.max(hi, cx + half)
					end
					return lo, hi
				end
				local fonts = {
					{ name = "Title", face = c.Theme.Fonts.Title, enum = Enum.Font.FredokaOne },
					{ name = "Stamp", face = c.Theme.Fonts.Stamp, enum = Enum.Font.LuckiestGuy },
				}
				for _, font in fonts do
					for _, marker in { c.Text.CROWN, c.Text.DROP } do
						for _, size in { 20, 32, 48 } do
							local l = label(c)
							l.FontFace = font.face
							c.Text.style(l, "label", size)
							c.h:settle(1)
							c.Text.raw(l, "A" .. marker .. "4")
							Layout.apply(c.h)
							local icon = c.Text.icons(l)[1]
							local lo, hi = extent(icon)
							local x = icon.Position.X.Offset
							local before = width("A", l.TextSize, font.enum)
							local after = width(string.sub(l.Text, 1, #l.Text - 1), l.TextSize, font.enum)
							local air = 0.1 * l.TextSize
							expect({
								font = font.name,
								icon = icon:GetAttribute("Icon"),
								size = size,
								airBefore = x + lo - before >= air,
								airAfter = after - (x + hi) >= air,
							}).toEqual({
								font = font.name,
								icon = icon:GetAttribute("Icon"),
								size = size,
								airBefore = true,
								airAfter = true,
							})
							l:Destroy()
						end
					end
				end
				clean(c)
			end
		)

		it("Glyph.crown et Glyph.drop : tailles hostiles bornées, jamais d'erreur", function()
			local c = setup()
			for _, size in { 0 / 0, -5, 0, 4, 1e9, 48 } do
				for _, make in { c.Glyph.crown, c.Glyph.drop } do
					local g = make(nil, size)
					expect(g.Size.X.Offset >= 8 and g.Size.X.Offset <= 512).toBe(true)
					g:Destroy()
				end
			end
			clean(c)
		end)

		it("Glyph.star : tailles hostiles bornées, jamais d'erreur", function()
			local c = setup()
			for _, size in { 0 / 0, -5, 0, 4, 1e9, 48 } do
				local s = c.Glyph.star(nil, size)
				expect(s.Size.X.Offset >= 8 and s.Size.X.Offset <= 512).toBe(true)
				s:Destroy()
			end
			clean(c)
		end)
	end)

	describe(
		"Text_icons › mots tenus ensemble (« {_} » : espace ordinaire qui ne coupe jamais)",
		function()
			local function boxed(c, w)
				local l = label(c)
				l.Size = UDim2.fromOffset(w, 200)
				l.TextWrapped = true
				Layout.apply(c.h)
				return l
			end

			it("boîte large : une ligne, espaces ordinaires, aucun repère ni U+00A0", function()
				local c = setup()
				local l = boxed(c, 600)
				c.Text.set(l, "plop.reward.day1")
				expect(l.Text).toBe("Autocollant Jour 1")
				expect(string.find(l.Text, "\194\160", 1, true)).toBeNil()
				clean(c)
			end)

			it(
				"boîte étroite : « Jour » et « 1 » jamais séparés ; retours posés par UI/Text",
				function()
					local c = setup()
					local l = boxed(c, 220)
					c.Text.set(l, "plop.reward.day1")
					expect(string.find(l.Text, "{_}", 1, true)).toBeNil()
					expect(string.find(l.Text, "Jour 1", 1, true) ~= nil).toBe(true)
					expect(string.find(l.Text, "\n", 1, true) ~= nil).toBe(true)
					-- chaque ligne tient dans la boîte (aucune coupure laissée au moteur)
					local TextService = c.h.game:GetService("TextService")
					for line in string.gmatch(l.Text .. "\n", "([^\n]*)\n") do
						local w = TextService:GetTextSize(
							line,
							l.TextSize,
							Enum.Font.FredokaOne,
							roblox.Vector2.new(1e5, 1e5)
						).X
						expect({ line = line, fits = w <= 220 + 0.5 }).toEqual({ line = line, fits = true })
					end
					-- la boîte s'élargit : une seule ligne de nouveau
					l.Size = UDim2.fromOffset(700, 200)
					Layout.apply(c.h)
					c.h:settle(1)
					expect(l.Text).toBe("Autocollant Jour 1")
					-- « BOOP RUSH » et « 1 sur » tenus aussi
					c.Prefs._onSettings({ lang = "fr" })
					c.Text.set(l, "card.mode.rush")
					l.Size = UDim2.fromOffset(240, 200)
					Layout.apply(c.h)
					c.h:settle(1)
					expect(string.find(l.Text, "BOOP RUSH", 1, true) ~= nil).toBe(true)
					clean(c)
				end
			)

			it("texte sans repère : rien n'est changé (aucun retour ajouté)", function()
				local c = setup()
				local l = boxed(c, 120)
				c.Text.raw(l, "Un texte assez long pour couper")
				expect(l.Text).toBe("Un texte assez long pour couper")
				clean(c)
			end)
		end
	)

	describe("Text_icons › vrai client : aucun « {*} » ni « ★ » affiché", function()
		local ok, c = pcall(Screens.boot, Harness, Screens.profileById("tv1080"), "fr", "late")
		if not ok then
			it("démarrage du client", function()
				error(c)
			end)
			return
		end
		-- tout l'écran : jamais un repère « {*} » ; le Ranch : jamais « ★ » (les symboles du rail du menu
		-- sont au lot B2, note INT-B1-RAIL)
		local function scan(where)
			local out = {}
			local playerGui = c.h.localPlayer:FindFirstChildOfClass("PlayerGui")
			local win = c.PC.window("Ranch")
			for _, d in playerGui:GetDescendants() do
				if (d:IsA("TextLabel") or d:IsA("TextButton")) and Layout.visible(d) then
					local inRanch = win ~= nil and d:IsDescendantOf(win)
					if
						string.find(d.Text, "{*}", 1, true)
						or (inRanch and string.find(d.Text, "★", 1, true))
					then
						table.insert(out, where .. " : " .. Layout.name(d) .. " « " .. d.Text .. " »")
					end
				end
			end
			return out
		end
		local bad = {}
		Screens.open(c, "Ranch", "pens")
		Screens.layout(c)
		for _, line in scan("Ranch › Enclos") do
			table.insert(bad, line)
		end
		local Text = c.h:require(Screens.CLIENT .. "UI.Text")
		local starred = 0
		local win = c.PC.window("Ranch")
		for _, d in win:GetDescendants() do
			if d:IsA("TextLabel") and #Text.icons(d) > 0 then
				starred += 1
			end
		end
		Screens.closeAll(c)
		it(
			"Ranch › Enclos (squishies à 5 étoiles) : étoiles dessinées, aucun repère ni « ★ »",
			function()
				expect(table.concat(bad, "\n")).toBe("")
				expect(starred >= 1).toBe(true)
			end
		)
		it("zéro trace", function()
			expect(table.concat(c.h.errors, "\n")).toBe("")
			expect(table.concat(c.h:warnings(), "\n")).toBe("")
		end)
		Harness.disposeAll()
	end)
end
