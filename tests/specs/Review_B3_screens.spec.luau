--!nocheck
-- Relecture des écrans et de la manette du lot B3 (écrans de renaissance et de méta) : défauts trouvés en
-- regardant les captures de l'outil d'écrans (tools/screens, groupe « meta », tv1080, tv720, tv2160, FR et
-- EN) et en parcourant chaque écran du lot à la manette sur le vrai client console ; chaque cas montré
-- rouge avant sa correction (docs/04 §27.12, lignes B3-79 et suivantes). Interrupteurs v2.0 ouverts DANS
-- le test (scénarios du groupe « meta » de tests/harness/Screens). Zéro trace.
local roblox = require("@lune/roblox")
local Screens = require("../harness/Screens")
local Layout = require("../harness/Layout")
local TextFit = require("../harness/TextFit")
local EngineProps = require("../harness/EngineProps")

local Enum = roblox.Enum

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	-- Cadre de focus (FocusGuard.selectionImage) : liseré sombre de 2 px au bord de l'élément, puis trait
	-- blanc de 6 px vers l'intérieur : les 8 px du bord de l'élément choisi sont couverts
	local BAND = 8

	-- Encre d'un texte (px d'écran) : lignes mesurées (TextFit, vraies largeurs des polices), alignées dans
	-- la boîte du libellé (UIPadding compris), contour du texte (UIStroke) compris ; nil si rien n'est vu
	local function inkOf(obj)
		local r = Layout.rect(obj)
		local d = TextFit.layout(obj)
		if r == nil or d == nil then
			return nil
		end
		local k = r.k or 1
		local pl, pt, pr, pb = table.unpack(d.pad or { 0, 0, 0, 0 })
		local bx, by = r.x + pl * k, r.y + pt * k
		local bw, bh = r.w - (pl + pr) * k, r.h - (pt + pb) * k
		local w, h = d.textWidth * k, d.textHeight * k
		local xa = EngineProps.get(obj, "TextXAlignment")
		local ya = EngineProps.get(obj, "TextYAlignment")
		local x = bx + (bw - w) / 2
		if xa == Enum.TextXAlignment.Left then
			x = bx
		elseif xa == Enum.TextXAlignment.Right then
			x = bx + bw - w
		end
		local y = by + (bh - h) / 2
		if ya == Enum.TextYAlignment.Top then
			y = by
		elseif ya == Enum.TextYAlignment.Bottom then
			y = by + bh - h
		end
		local s = 0
		for _, ch in obj:GetChildren() do
			if ch.ClassName == "UIStroke" and EngineProps.get(ch, "Enabled") ~= false then
				s = math.max(s, (EngineProps.get(ch, "Thickness") or 0) * k)
			end
		end
		local x0, y0, x1, y1 = x - s, y - s, x + w + s, y + h + s
		if r.clip then
			x0, y0 = math.max(x0, r.clip.x), math.max(y0, r.clip.y)
			x1, y1 = math.min(x1, r.clip.x + r.clip.w), math.min(y1, r.clip.y + r.clip.h)
		end
		if x1 <= x0 or y1 <= y0 then
			return nil
		end
		return { x0 = x0, y0 = y0, x1 = x1, y1 = y1, text = d.text, k = k }
	end

	-- Textes de l'élément sélectionnable `e` dont l'encre entre dans la bande du cadre de focus (le cadre
	-- les couvrirait quand e est choisi) : « <px> <chemin> « texte » »
	local function underFrame(e)
		local out = {}
		local er = Layout.rect(e)
		if er == nil or not Layout.visible(e) then
			return out
		end
		local k = er.k or 1
		local ix0, iy0 = er.x + BAND * k, er.y + BAND * k
		local ix1, iy1 = er.x + er.w - BAND * k, er.y + er.h - BAND * k
		local list = { e }
		for _, d in e:GetDescendants() do
			table.insert(list, d)
		end
		for _, d in list do
			if
				TextFit.isText(d)
				and Layout.visible(d)
				and (EngineProps.get(d, "TextTransparency") or 0) < 0.99
				and string.find(TextFit.displayText(d), "[%w\195\197]")
			then
				local ink = inkOf(d)
				if ink then
					local over = math.max(ix0 - ink.x0, iy0 - ink.y0, ink.x1 - ix1, ink.y1 - iy1)
					if over > 0.5 * k then
						table.insert(
							out,
							string.format("%.1f px : %s « %s »", over / k, Layout.name(d), ink.text)
						)
					end
				end
			end
		end
		return out
	end

	local function metaScreen(id)
		for _, group in Screens.groups() do
			if group.id == "meta" then
				for _, screen in group.screens do
					if screen.id == id then
						return group, screen
					end
				end
			end
		end
		error("écran inconnu : " .. id)
	end

	-- Défaut 1 (B3-79) : le cadre de focus (8 px dedans) couvrait le début et la fin des noms et des
	-- sources des cases de Mon style (libellés à 6 px du bord de la case : « Dragon de gelée » lu
	-- « )ragon de gelée » sur la case choisie, « Selle « Biscuit » », « Saddles & Trails pass »,
	-- « Squishydex : 260 tampons ») et les deux lignes de « Couleurs du Splorch » dans la liste des sortes
	-- (bouton de 72 px rempli). Chaque case de chaque sorte, profils riche (« Équiper ») et pauvre
	-- (sources des cadenas), choix des objets de Déco perso (petits et grands), EN et FR.
	describe("Review_B3_screens › Mon style : le cadre de focus ne couvre aucun texte", function()
		local profile = Screens.profileById("tv1080")
		for _, lang in Screens.LANGS do
			for _, base in { "meta.style.theme", "meta.style.locked" } do
				it(
					lang .. " · " .. base .. " : chaque sorte, chaque case, le choix de la Déco perso",
					function()
						local group, screen = metaScreen(base)
						local c = Screens.boot(Harness, profile, lang, group.state)
						local shown, err = Screens.show(c, screen)
						expect(err).toBeNil()
						expect(shown).toBe(true)
						local Ranch = c.h:require(Screens.CLIENT .. "UI.Panels.Ranch")
						local GuiService = c.h.game.GuiService
						local problems, seen = {}, {}
						local function note(list)
							for _, line in list do
								if not seen[line] then
									seen[line] = true
									table.insert(problems, line)
								end
							end
						end
						local function look(obj)
							GuiService.SelectedObject = obj
							Screens.frames(c, 3, 0.1)
							Screens.layout(c)
							note(underFrame(obj))
						end
						local function walkEntries()
							for _, e in Ranch._styleEntries() do
								local cell = Ranch._styleCell(e.kind, e.id)
								if cell then
									look(cell)
								end
							end
						end
						local kinds = Ranch._state().kinds
						expect(#kinds >= 9).toBe(true)
						for _, kind in kinds do
							local b = Ranch._styleKindButton(kind)
							expect(b ~= nil).toBe(true)
							look(b)
							if kind ~= "deco" then
								Screens.activate(c, b)
								walkEntries()
							end
						end
						-- choix d'un objet de Déco perso : emplacement petit (2) puis grand (9)
						for _, slot in { 2, 9 } do
							Screens.activate(c, Ranch._styleKindButton("deco"))
							local s = Ranch._decoSlot(slot)
							expect(s ~= nil).toBe(true)
							look(s)
							Screens.activate(c, s)
							expect(Ranch._state().pickerSlot).toBe(slot)
							walkEntries()
							GuiService.SelectedObject = nil
						end
						table.sort(problems)
						expect(table.concat(problems, "\n")).toBe("")
						Harness.disposeAll()
					end
				)
			end
		end
		it("fin des écrans", function()
			Screens.finish()
		end)
	end)
end
