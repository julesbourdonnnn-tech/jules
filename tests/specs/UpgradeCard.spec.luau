--!nocheck
-- UpgradeCard (lot B2, étape 1 ; docs/04 §27.7, §27.8 règles 2, 7, 10, 11, 18, 20 ; GDD v2.0 §10.7.4 à
-- §10.7.6) : le composant unique de l'écran Améliorations, en 3 gabarits (carte 432 × 528, ligne
-- 1 328 × 112, tuile 400 × 300), dans le VRAI client :
--   * chaque gabarit, dans chacun des 7 états du §10.7.6, en français et en anglais, avec les pires
--     valeurs (« 1,00e300 », « 99,9Nvvg », « 40/40 », « Record 400 », « Boucle 10 », noms et libellés
--     les plus longs) : chaque objet visible reste dans le rectangle du gabarit, chaque texte tient
--     (TextFit : ni débord, ni mot coupé, ni texte sous 28 px de référence), à 1080p et à 720p ;
--   * aucun caractère hors des polices (table cmap de FredokaOne et de LuckiestGuy, règle 18) ;
--   * chaque état = un dessin ET un mot (jamais la couleur seule) ; carte prête : dessin du bouton
--     « Acheter » avec le glyphe de l'appareil ; flèche DESSINÉE entre l'avant et l'après ;
--   * set() ne crée aucune instance (règles 2 et 20) ; FocusId = identifiant de la ligne ; ombre sur la
--     carte seulement (INT-B1-SHADOW) ; budget d'instances de chaque gabarit relevé ;
--   * « ×3 à chaque boucle, pour toujours » (ascend.tile.growth) tient en 2 lignes à 36 px dans la tuile.
-- Les vues viennent de UI/Hud/UpgradeView (instantanés fabriqués, interrupteurs v2.0 ouverts DANS le
-- test). Zéro trace.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Layout = require("../harness/Layout")
local TextFit = require("../harness/TextFit")
local FontCmap = require("../harness/FontCmap")

local UDim2 = roblox.UDim2
local Vector2 = roblox.Vector2
local Enum = roblox.Enum

local WITNESS = serde.decode("json", fs.readFile("tests/fixtures/profiles/v2.json"))
local CMAPS = FontCmap.load()

local function deepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in t do
		out[k] = deepCopy(v)
	end
	return out
end

local STATES = { "ready", "need", "max", "locked", "loopCap", "busy", "retry" }
local TEMPLATES = { "card", "row", "tile" }

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function clean(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	local function setup(lang, viewport)
		local h = TvAudit.client({ lang = lang, viewport = viewport })
		local c = {
			h = h,
			lang = lang,
			Card = TvAudit.mod(h, "UI.UpgradeCard"),
			V = TvAudit.mod(h, "UI.Hud.UpgradeView"),
			Icons = TvAudit.mod(h, "UI.Hud.Icons"),
			Root = TvAudit.mod(h, "UI.Root"),
			UpgradeMath = h:require("ReplicatedStorage.Shared.Logic.UpgradeMath"),
			Features = h:require("ReplicatedStorage.Shared.Config.Features"),
		}
		c.ON = {}
		for k, v in c.Features.Defaults do
			c.ON[k] = if type(v) == "boolean" then true else v
		end
		c.screen = c.Root.safe("UpgradeCardTest", 20)
		return c
	end

	local function snapOf(c, edit)
		local p = deepCopy(WITNESS)
		if edit then
			edit(p)
		end
		return c.UpgradeMath.snapshot(p, c.ON, 1)
	end

	-- Vue réelle de chaque état (UpgradeView), mode `mode`
	local function stateView(c, state, mode)
		local rich = function(p)
			p.coins = 1e300
		end
		if state == "ready" then
			return c.V.view("gloves", snapOf(c, rich), mode, { lang = c.lang })
		elseif state == "need" then
			return c.V.view(
				"gloves",
				snapOf(c, function(p)
					p.coins = 0
				end),
				mode,
				{ lang = c.lang }
			)
		elseif state == "max" then
			return c.V.view("pens", snapOf(c, rich), mode, { lang = c.lang })
		elseif state == "locked" then
			return c.V.view(
				"gloves",
				snapOf(c, function(p)
					p.R = 0
					p.bestR = 0
				end),
				mode,
				{ lang = c.lang }
			)
		elseif state == "loopCap" then
			return c.V.view(
				"snack",
				snapOf(c, function(p)
					p.R = 3
					p.bestR = 15
					p.ascend = 1
					p.tiles.snack = 12
					p.tiles.star = 0
				end),
				mode,
				{ lang = c.lang }
			)
		end
		return c.V.view("gloves", snapOf(c, rich), mode, { lang = c.lang }, state)
	end

	-- Pires valeurs posées sur une vue (mêmes formes que les formateurs)
	local function worst(v, which)
		local w = table.clone(v)
		w.priceText = if which == 1 then "1,00e300" else "99,9Nvvg"
		w.levelText = "40/40"
		w.fromText = "40"
		w.toText = "40"
		w.name = { key = "upgrades.family.school" } -- « École des Plopettes »
		w.tier = { key = "upgrades.tier.gloves.5" } -- « Guimauve »
		w.reason = { key = "upgrades.reason.helpers" }
		w.effect = {
			label = { key = "upgrades.effect.presses" },
			before = { key = "upgrades.unit.mult", vars = { n = "1,975" } },
			after = { key = "upgrades.unit.mult", vars = { n = "2,000" } },
		}
		w.cardLevel = {
			before = { key = "common.level", vars = { n = "40" } },
			after = { key = "upgrades.unit.count", vars = { n = "40" } },
		}
		if v.state == "locked" then
			w.stateText = { key = "upgrades.state.locked", vars = { r = "400" } }
		elseif v.state == "loopCap" then
			w.stateText = { key = "upgrades.state.loopCap", vars = { r = "10" } }
		end
		return w
	end

	local function place(c, card)
		card.root.Position = UDim2.fromOffset(40, 40)
		card.root.Parent = c.screen
	end

	-- Colonnes fixes d'une ligne (Config/Layout.Upgrades.Columns, GDD §10.7.5) : chaque élément dans la
	-- sienne (le coin de l'icône déborde vers la droite de l'icône, jamais dans la colonne Texte)
	local ROW_COLUMNS = {
		Icon = "icon",
		Badge = "badge",
		Name = "text",
		EffectLabel = "text",
		Before = "text",
		EffectArrow = "text",
		After = "text",
		LevelA = "level",
		LevelArrow = "level",
		LevelB = "level",
		LevelBar = "level",
		Currency = "effect",
		Price = "effect",
		PriceBar = "effect",
		StateIcon = "state",
		Word = "state",
	}

	local function columnIssues(c, card, box, what)
		local Columns = c.h:require("ReplicatedStorage.Shared.Config.Layout").Upgrades.Columns
		local k = box.w / 1328
		local out = {}
		for _, d in card.root:GetChildren() do
			local col = ROW_COLUMNS[d.Name]
			if col and d:IsA("GuiObject") and Layout.visible(d) then
				local r = Layout.rect(d)
				local x0, x1
				if col == "badge" then
					x0, x1 = Columns.icon.x, Columns.text.x
				else
					x0, x1 = Columns[col].x, Columns[col].x + Columns[col].w
				end
				local left, right = box.x + x0 * k, box.x + x1 * k
				if r.x < left - 0.5 or r.x + r.w > right + 0.5 then
					table.insert(out, string.format("%s : %s hors de sa colonne %s", what, d.Name, col))
				end
			end
		end
		return out
	end

	-- Objets visibles hors du rectangle du gabarit (ligne : hors de leur colonne), textes qui ne tiennent pas
	local function audit(c, card, what)
		Layout.apply(c.h)
		local issues = {}
		local box = Layout.rect(card.root)
		expect(box ~= nil).toBe(true)
		if card.template == "row" then
			for _, msg in columnIssues(c, card, box, what) do
				table.insert(issues, msg)
			end
		end
		for _, d in card.root:GetDescendants() do
			if d:IsA("GuiObject") and Layout.visible(d) then
				local r = Layout.rect(d)
				if r then
					local out = r.x < box.x - 0.5
						or r.y < box.y - 0.5
						or r.x + r.w > box.x + box.w + 0.5
						or r.y + r.h > box.y + box.h + 0.5
					if out then
						table.insert(issues, string.format("%s : %s hors du gabarit", what, d:GetFullName()))
					end
				end
				if d:IsA("TextLabel") and d.Text ~= "" then
					local ok, details = TextFit.fits(d)
					if not ok then
						for _, issue in details.issues do
							table.insert(
								issues,
								string.format("%s : %s « %s » %s", what, d.Name, d.Text, issue.message)
							)
						end
					end
					local missing = FontCmap.missing(CMAPS, d.Text)
					if #missing > 0 then
						table.insert(
							issues,
							string.format(
								"%s : %s « %s » hors police %s",
								what,
								d.Name,
								d.Text,
								table.concat(missing, ", ")
							)
						)
					end
				end
			end
		end
		return issues
	end

	describe("UpgradeCard › 3 gabarits × 7 états (règle 11), pires valeurs, EN et FR", function()
		for _, lang in { "fr", "en" } do
			for _, res in { { name = "1080p", size = nil }, { name = "720p", size = Vector2.new(1280, 720) } } do
				it(
					string.format(
						"%s, %s : tout dans son rectangle, chaque texte tient, aucun caractère hors police",
						lang,
						res.name
					),
					function()
						local c = setup(lang, res.size)
						local issues = {}
						for _, template in TEMPLATES do
							local card = c.Card.new(template, nil)
							place(c, card)
							for _, state in STATES do
								for _, mode in { 1, 10, 0 } do
									local v = stateView(c, state, mode)
									expect(v.state).toBe(state)
									for _, view in { v, worst(v, 1), worst(v, 2) } do
										if template == "tile" then
											view = table.clone(view)
											view.name = { key = "ascend.tile.growth" }
										end
										card:set(state, view)
										for _, msg in audit(c, card, template .. "/" .. state .. "/" .. mode) do
											table.insert(issues, msg)
										end
									end
								end
							end
						end
						expect(table.concat(issues, "\n")).toBe("")
						clean(c.h)
					end
				)
			end
		end
	end)

	describe("UpgradeCard › un dessin et un mot pour chaque état (jamais la couleur seule)", function()
		it(
			"carte et ligne : dessin de l'état (ou glyphe du bouton « Acheter ») et mot visibles",
			function()
				local c = setup("fr")
				for _, template in { "card", "row" } do
					local card = c.Card.new(template, nil)
					place(c, card)
					for _, state in STATES do
						local v = stateView(c, state, 1)
						card:set(state, v)
						Layout.apply(c.h)
						local p = card.parts
						expect(p.word.Visible).toBe(true)
						expect(p.word.Text ~= "").toBe(true)
						expect(card.root:GetAttribute("State")).toBe(state)
						if template == "card" and state == "ready" then
							-- dessin du bouton « Acheter » : pilule, glyphe de l'appareil, mot
							expect(p.pill.Visible).toBe(true)
							expect(p.word.Text).toBe("Acheter")
							expect(c.Icons.kindOf(p.stateIcon)).toBe(nil)
						else
							expect(c.Icons.kindOf(p.stateIcon)).toBe(c.V.STATE_ICONS[state])
							if p.pill then
								expect(p.pill.Visible).toBe(false)
							end
						end
					end
				end
				clean(c.h)
			end
		)

		it(
			"flèche dessinée entre l'avant et l'après (aucun caractère « → »), cachée sans valeur après",
			function()
				local c = setup("fr")
				local row = c.Card.new("row", nil)
				place(c, row)
				local g = stateView(c, "ready", 1)
				row:set("ready", g)
				expect(c.Icons.kindOf(row.parts.effectArrow)).toBe("arrowRight")
				expect(row.parts.before.Text).toBe("×1,000")
				expect(row.parts.after.Text).toBe("×1,025")
				for _, d in row.root:GetDescendants() do
					if d:IsA("TextLabel") then
						expect(string.find(d.Text, "→", 1, true)).toBe(nil)
					end
				end
				local max = stateView(c, "max", 1)
				row:set("max", max)
				expect(c.Icons.kindOf(row.parts.effectArrow)).toBe(nil)
				expect(row.parts.after.Visible).toBe(false)
				-- ×10 : colonne Niveau « 0 » → « 10 » avec la flèche dessinée
				local bulk = stateView(c, "ready", 10)
				row:set("ready", bulk)
				expect(row.parts.levelA.Text).toBe("0")
				expect(row.parts.levelB.Text).toBe("10")
				expect(c.Icons.kindOf(row.parts.levelArrow)).toBe("arrowRight")
				-- ×1 : « 0/40 », pas de flèche
				row:set("ready", g)
				expect(row.parts.levelA.Text).toBe("0/40")
				expect(row.parts.levelB.Visible).toBe(false)
				expect(c.Icons.kindOf(row.parts.levelArrow)).toBe(nil)
				clean(c.h)
			end
		)
	end)

	describe("UpgradeCard › construit une fois (règles 2 et 20)", function()
		it(
			"set() et feedback() ne créent aucune instance (3 gabarits, 7 états, 3 modes, 2 langues)",
			function()
				local c = setup("fr")
				local cards = {}
				for _, template in TEMPLATES do
					local card = c.Card.new(template, nil)
					place(c, card)
					table.insert(cards, card)
				end
				Layout.apply(c.h)
				local playerGui = c.h.localPlayer.PlayerGui
				local before = #playerGui:GetDescendants()
				for round = 1, 3 do
					for _, card in cards do
						for _, state in STATES do
							for _, mode in { 1, 10, 0 } do
								local v = stateView(c, state, mode)
								card:set(state, v)
								card:set(state, worst(v, round % 2 + 1))
								card:feedback({ key = "upgrades.bought", vars = { n = "7", price = "1,2M" } })
								card:set(state, v)
								card:feedback(nil)
							end
						end
					end
					TvAudit.setLanguage(c.h, if round == 2 then "en" else "fr")
				end
				Layout.apply(c.h)
				expect(#playerGui:GetDescendants()).toBe(before)
				clean(c.h)
			end
		)

		it(
			"FocusId = identifiant de la ligne ; ombre sur la carte seulement ; budget de chaque gabarit relevé",
			function()
				local c = setup("fr")
				local card = c.Card.new("card", c.screen)
				local row = c.Card.new("row", c.screen)
				local tile = c.Card.new("tile", c.screen)
				card:set("ready", stateView(c, "ready", 1))
				row:set("max", stateView(c, "max", 1))
				tile:set("ready", stateView(c, "ready", 1))
				expect(card.root:GetAttribute("FocusId")).toBe("gloves")
				expect(row.root:GetAttribute("FocusId")).toBe("pens")
				expect(tile.root:GetAttribute("FocusId")).toBe(nil)
				expect(card.root.Selectable).toBe(true)
				expect(row.root.Selectable).toBe(true)
				expect(tile.root.Selectable).toBe(false)
				-- ombre : UIShadow du moteur ou ombre de repli (cadre frère « _Shadow »)
				local function shadowed(obj)
					if obj:FindFirstChildOfClass("UIShadow") then
						return true
					end
					return obj.Parent:FindFirstChild(obj.Name .. "_Shadow") ~= nil
				end
				expect(shadowed(card.root)).toBe(true)
				expect(shadowed(row.root)).toBe(false)
				expect(shadowed(tile.root)).toBe(false)
				-- budget (règle 20 : écran entier ≤ 1 400) : vues par défaut (toutes les sortes) et réglées
				local function count(obj)
					return #obj:GetDescendants() + 1
				end
				local exactRow = c.Card.new(
					"row",
					c.screen,
					{ icons = { "glove" }, badges = { "loop" }, currencies = { "coin" } }
				)
				local exactAtelier = c.Card.new(
					"row",
					c.screen,
					{ icons = { "magnet" }, badges = { "star" }, currencies = { "confetti" } }
				)
				local counts = {
					card = count(card.root),
					row = count(row.root),
					tile = count(tile.root),
					rowExact = count(exactRow.root),
					rowAtelier = count(exactAtelier.root),
				}
				print(
					string.format(
						"    instances : carte %d, ligne %d (réglée %d, Atelier %d), tuile %d",
						counts.card,
						counts.row,
						counts.rowExact,
						counts.rowAtelier,
						counts.tile
					)
				)
				-- relevé du lot B2, étape 1 (garde contre une régression ; le budget de l'écran entier est la
				-- spec Upgrades_Budget de l'étape 2) : carte 83, ligne de toutes les sortes 86, ligne réglée
				-- 66 (Atelier 77), tuile 33
				expect(counts.card <= 83).toBe(true)
				expect(counts.row <= 86).toBe(true)
				expect(counts.rowExact <= 66).toBe(true)
				expect(counts.rowAtelier <= 77).toBe(true)
				expect(counts.tile <= 33).toBe(true)
				clean(c.h)
			end
		)
	end)

	describe("UpgradeCard › tuile des aperçus (lot B3)", function()
		it(
			"« ×3 à chaque boucle, pour toujours » (ascend.tile.growth) tient en 2 lignes à 36 px",
			function()
				local c = setup("fr")
				local tile = c.Card.new("tile", nil)
				place(c, tile)
				local v = table.clone(stateView(c, "ready", 1))
				v.name = { key = "ascend.tile.growth" }
				v.value = { key = "ascend.tile.confetti", vars = { n = "99999" } }
				tile:set("ready", v)
				Layout.apply(c.h)
				local title = tile.parts.name
				expect(title.Text).toBe("×3 à chaque boucle, pour toujours")
				local ok, d = TextFit.fits(title)
				expect(ok).toBe(true)
				expect(#d.lines <= 2).toBe(true)
				expect(#d.lines).toBe(2) -- 483 px à 36 px : 2 lignes dans 368
				expect(d.size).toBe(36)
				expect(tile.parts.word.Text).toBe("+99999 Confettis")
				expect(c.Icons.kindOf(tile.parts.stateIcon)).toBe(nil)
				clean(c.h)
			end
		)
	end)

	-- Défauts vus sur les captures de l'étape 1 (outil d'écrans, tv1080 / tv720 / tv2160, FR et EN) :
	-- chacun montré rouge avant la correction de UI/UpgradeCard
	describe("UpgradeCard › relecture des captures (lot B2, étape 1)", function()
		local function centerX(r)
			return r.x + r.w / 2
		end

		it(
			"Monuments : « Revenu +3 % », flèche dessinée et « +4 % » (le libellé porte la valeur d'avant), ligne et carte",
			function()
				local c = setup("fr")
				local v = c.V.view(
					"monument",
					snapOf(c, function(p)
						p.tiles.monuments = 3
						p.bestR = 12
						p.tiles.snack = 12
						p.coins = 1e300
					end),
					1,
					{ lang = "fr" }
				)
				expect(v.state).toBe("ready")
				for _, template in { "row", "card" } do
					local card = c.Card.new(template, nil)
					place(c, card)
					card:set(v.state, v)
					Layout.apply(c.h)
					local p = card.parts
					expect(p.effectLabel.Visible).toBe(true)
					expect(p.effectLabel.Text).toBe("Revenu +3 %")
					expect(p.before.Visible).toBe(false)
					expect(c.Icons.kindOf(p.effectArrow)).toBe("arrowRight")
					expect(p.after.Visible).toBe(true)
					expect(p.after.Text).toBe("+4 %")
					local label, arrow, after =
						Layout.rect(p.effectLabel), Layout.rect(p.effectArrow), Layout.rect(p.after)
					expect(arrow.x + arrow.w <= after.x + 0.5).toBe(true)
					if template == "row" then
						-- ligne : « Revenu +3 % » finit contre la flèche (même colonne que « ×1,000 » des Gants)
						expect(label.x + label.w <= arrow.x + 0.5).toBe(true)
						expect(p.effectLabel.TextXAlignment).toBe(Enum.TextXAlignment.Right)
						local ok = TextFit.fits(p.effectLabel)
						expect(ok).toBe(true)
					end
					expect(table.concat(audit(c, card, template .. "/monument"), "\n")).toBe("")
					-- au maximum : le libellé seul, sans flèche ni valeur après
					local max = c.V.view(
						"monument",
						snapOf(c, function(p2)
							p2.tiles.monuments = 10
							p2.bestR = 24
							p2.tiles.snack = 12
						end),
						1,
						{ lang = "fr" }
					)
					expect(max.state).toBe("max")
					card:set(max.state, max)
					expect(p.effectLabel.Text).toBe("Revenu +10 %")
					expect(p.after.Visible).toBe(false)
					expect(c.Icons.kindOf(p.effectArrow)).toBe(nil)
					card.root:Destroy()
				end
				clean(c.h)
			end
		)

		it(
			"carte au MAX : le niveau seul et la valeur seule sont centrés sur la carte (aucune moitié vide)",
			function()
				local c = setup("fr")
				local card = c.Card.new("card", nil)
				place(c, card)
				local box
				local p = card.parts
				-- MAX : « Niv. 14 » et « 18 » centrés
				card:set("max", stateView(c, "max", 1))
				Layout.apply(c.h)
				box = Layout.rect(card.root)
				expect(p.levelA.Text).toBe("Niv. 14")
				expect(p.levelB.Visible).toBe(false)
				expect(p.levelA.TextXAlignment).toBe(Enum.TextXAlignment.Center)
				expect(math.abs(centerX(Layout.rect(p.levelA)) - centerX(box)) <= 1).toBe(true)
				expect(p.before.Visible).toBe(true)
				expect(p.after.Visible).toBe(false)
				expect(p.before.TextXAlignment).toBe(Enum.TextXAlignment.Center)
				expect(math.abs(centerX(Layout.rect(p.before)) - centerX(box)) <= 1).toBe(true)
				-- puis prête : de nouveau « avant » à droite de sa moitié, flèche, « après »
				card:set("ready", stateView(c, "ready", 1))
				Layout.apply(c.h)
				expect(p.levelA.TextXAlignment).toBe(Enum.TextXAlignment.Right)
				expect(p.before.TextXAlignment).toBe(Enum.TextXAlignment.Right)
				local la, arrow = Layout.rect(p.levelA), Layout.rect(p.levelArrow)
				expect(la.x + la.w <= arrow.x + 0.5).toBe(true)
				local b, ea = Layout.rect(p.before), Layout.rect(p.effectArrow)
				expect(b.x + b.w <= ea.x + 0.5).toBe(true)
				clean(c.h)
			end
		)

		it(
			"ligne sans seconde ligne (« Pour le plaisir ») : le nom est centré en hauteur, puis revient en haut",
			function()
				local c = setup("fr")
				local row = c.Card.new("row", nil)
				place(c, row)
				local rich = snapOf(c, function(p)
					p.coins = 1e300
					p.confetti = 1e6
				end)
				local fun = c.V.view("fun.title", rich, 1, { lang = "fr" })
				expect(fun.effect).toBe(nil)
				row:set(fun.state, fun)
				Layout.apply(c.h)
				local box = Layout.rect(row.root)
				local name = Layout.rect(row.parts.name)
				expect(row.parts.effectLabel.Visible).toBe(false)
				expect(math.abs((name.y + name.h / 2) - (box.y + box.h / 2)) <= 1).toBe(true)
				-- une ligne avec un avant → après : le nom revient sur la première ligne
				row:set("ready", stateView(c, "ready", 1))
				Layout.apply(c.h)
				name = Layout.rect(row.parts.name)
				expect(name.y + name.h <= Layout.rect(row.parts.effectLabel).y + 0.5).toBe(true)
				clean(c.h)
			end
		)
	end)
end
