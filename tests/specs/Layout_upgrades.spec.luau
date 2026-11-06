--!nocheck
-- Layout_upgrades (lot B2, étape 2 ; docs/04 §27.8 règles 10, 11, 13 ; GDD v2.0 §10.7.3 à §10.7.5) :
-- disposition de l'écran Améliorations sur le VRAI client, à 1280 × 720, 1920 × 1080 et 3840 × 2160,
-- en anglais et en français, avec les pires valeurs (pièces 1e300, Gants 39/40, Record 400) :
--   * chaque zone du panneau à sa place (en-tête 12 → 100, onglets 100 → 164, contenu 164 → 724,
--     bandeau 724 → 844, marges de 32) : en-tête, onglets, cartes, lignes et bandeau dedans ;
--   * chaque objet visible d'une carte ou d'une ligne DANS sa carte ou sa ligne (aucun débord) ;
--     chaque carte dans la zone de 560 ; les lignes à 24 px des bords du cadre de défilement ;
--   * hauteur de défilement = fonction pure Σ hauteurs + (n − 1) × 16 (un titre de section = 112) ;
--   * aucun parent avec deux UI*Layout ; rien dans l'en-tête ne se chevauche ; la rangée des onglets
--     laisse la place à L2 / R2 et au bouton Fermer (D5) ;
--   * onglet Plopettes avant Pip (§10.7.5) : cadenas dessiné ET mot « Record 2 » dans l'onglet, sans
--     chevauchement, lisibles (contraste ≥ 3) sur l'onglet actif comme inactif ; après Pip : rien.
-- Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Layout = require("../harness/Layout")
local UpgradeScreen = require("../harness/UpgradeScreen")

local Vector2 = roblox.Vector2

local LAYOUTS = { UIListLayout = true, UIGridLayout = true, UITableLayout = true, UIPageLayout = true }

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect
	local S = UpgradeScreen.new(T.Harness)
	local U = S.Layout.Upgrades
	local EPS = 0.75

	local function inside(r, box)
		return r.x >= box.x - EPS
			and r.y >= box.y - EPS
			and r.x + r.w <= box.x + box.w + EPS
			and r.y + r.h <= box.y + box.h + EPS
	end

	local function name(obj)
		return Layout.name(obj)
	end

	-- Les objets visibles de `root` hors de son rectangle (messages)
	local function overflow(root)
		local out = {}
		local box = Layout.rect(root)
		if box == nil then
			return { name(root) .. " : aucun rectangle" }
		end
		for _, d in root:GetDescendants() do
			if d:IsA("GuiObject") and Layout.visible(d) then
				local r = Layout.rect(d)
				if r and r.w > 0 and r.h > 0 and not inside(r, box) then
					table.insert(out, string.format("%s hors de %s", name(d), name(root)))
				end
			end
		end
		return out
	end

	-- Rapport de contraste WCAG entre deux Color3 (objet non textuel ou grand texte : ≥ 3)
	local function luminance(c3)
		local function channel(v)
			return if v <= 0.03928 then v / 12.92 else ((v + 0.055) / 1.055) ^ 2.4
		end
		return 0.2126 * channel(c3.R) + 0.7152 * channel(c3.G) + 0.0722 * channel(c3.B)
	end
	local function contrast(a, b)
		local la, lb = luminance(a), luminance(b)
		if la < lb then
			la, lb = lb, la
		end
		return (la + 0.05) / (lb + 0.05)
	end

	local function rectOf(panel, k, y, h)
		return { x = panel.x + U.Margin * k, y = panel.y + y * k, w = (1440 - 2 * U.Margin) * k, h = h * k }
	end

	local function huge(p)
		for k, v in { snack = 11, decor = 17, gloves = 39, monuments = 4 } do
			p.tiles[k] = v
		end
		-- boucle 399 sous le Record R 400 : la pastille Souvenir est montrée (sa place est mesurée)
		p.R = 399
		p.bestR = 400
		p.coins = 1e300
		p.confetti = 99999
	end

	describe("Layout_upgrades › 3 résolutions × 2 langues, pires valeurs", function()
		it(
			"zones, cartes, lignes et en-tête en place ; aucun débord ; un seul UI*Layout par parent",
			function()
				local c = S.client({ snap = S.snap(1, huge) })
				local issues = {}
				local function note(msg)
					table.insert(issues, msg)
				end
				for _, res in { Vector2.new(1280, 720), Vector2.new(1920, 1080), Vector2.new(3840, 2160) } do
					for _, lang in { "en", "fr" } do
						local tag = string.format("%dx%d %s", res.X, res.Y, lang)
						TvAudit.setResolution(c.h, res)
						TvAudit.setLanguage(c.h, lang)
						for _, tab in { "suggested", "ranch", "helpers", "workshop" } do
							S.open(c, tab)
							Layout.apply(c.h)
							local win = c.PC.window("Upgrades")
							local panel = Layout.rect(win)
							local k = panel.w / 1440
							-- zones calculées depuis le panneau (règle 10)
							local header = rectOf(panel, k, U.Header.y, U.Header.h)
							local tabs = rectOf(panel, k, U.Tabs.y, U.Tabs.h)
							local content = rectOf(panel, k, U.Content.y, U.Content.h)
							local detail = rectOf(panel, k, U.Detail.y, U.Detail.h)
							local body = win:FindFirstChild("Body")
							for _, n in
								{
									"Title",
									"Memory",
									"CoinsIcon",
									"Coins",
									"ConfettiIcon",
									"Confetti",
									"Mode",
								}
							do
								local obj = body:FindFirstChild(n)
								local r = obj and Layout.rect(obj)
								if r == nil or not inside(r, header) then
									note(tag .. " " .. tab .. " : " .. n .. " hors de l'en-tête")
								end
							end
							-- l'en-tête ne se chevauche pas (places fixes, de gauche à droite)
							local order = {
								"Title",
								"Memory",
								"CoinsIcon",
								"Coins",
								"ConfettiIcon",
								"Confetti",
								"Mode",
							}
							for i = 1, #order - 1 do
								local a = Layout.rect(body:FindFirstChild(order[i]))
								local b = Layout.rect(body:FindFirstChild(order[i + 1]))
								if a == nil or b == nil or a.x + a.w > b.x + EPS then
									note(tag .. " : " .. order[i] .. " chevauche " .. order[i + 1])
								end
							end
							for _, id in { "suggested", "ranch", "helpers", "workshop" } do
								local r = Layout.rect(c.Up._tab(id))
								if r == nil or not inside(r, tabs) then
									note(tag .. " : onglet " .. id .. " hors de sa rangée")
								end
							end
							-- D5 : la rangée des onglets laisse L2 / R2 et Fermer à son bout, sans chevauchement
							local close = Layout.rect(body:FindFirstChild("Close"))
							local last = Layout.rect(c.Up._tab("workshop"))
							if
								close == nil
								or not inside(close, tabs)
								or last.x + last.w > close.x - 2 * 56 * k
							then
								note(tag .. " : Fermer, L2 et R2 sans place au bout des onglets")
							end
							local banner = Layout.rect(c.Up._banner())
							if banner == nil or not inside(banner, detail) then
								note(tag .. " : bandeau hors de sa zone")
							end
							if tab == "suggested" then
								for i = 1, 3 do
									local card = c.Up._card(i)
									if not inside(Layout.rect(card), content) then
										note(tag .. " : carte " .. i .. " hors de la zone de 560")
									end
									for _, m in overflow(card) do
										note(tag .. " : " .. m)
									end
								end
							else
								local sf = c.Up._list(tab)
								local box = Layout.rect(sf)
								if not inside(box, content) then
									note(tag .. " : liste " .. tab .. " hors de la zone de contenu")
								end
								for _, id in c.Up._shown(tab) do
									local row = c.Up._row(id)
									local r = Layout.rect(row)
									if
										math.abs((r.x - box.x) - 24 * k) > 1
										or math.abs(r.w - U.Row.w * k) > 1
									then
										note(tag .. " : ligne " .. id .. " pas à 24 px des bords")
									end
									for _, m in overflow(row) do
										note(tag .. " : " .. m)
									end
								end
							end
						end
					end
				end
				-- un seul UI*Layout par parent (règle du GDD §10.1)
				for _, d in c.PC.window("Upgrades"):GetDescendants() do
					local n = 0
					for _, child in d:GetChildren() do
						if LAYOUTS[child.ClassName] then
							n += 1
						end
					end
					if n > 1 then
						note(name(d) .. " : " .. n .. " UI*Layout")
					end
				end
				expect(table.concat(issues, "\n")).toBe("")
				S.clean(c, expect)
			end
		)

		it(
			"hauteur de défilement : Σ hauteurs + (n − 1) × 16, titre de section compté pour 112",
			function()
				local c = S.client({ snap = S.snap(1) })
				S.open(c, "ranch")
				expect(c.Up.canvasHeight({})).toBe(0)
				expect(c.Up.canvasHeight({ 112 })).toBe(112)
				expect(c.Up.canvasHeight({ 112, 112, 112 })).toBe(3 * 112 + 2 * 16)
				-- 6 lignes du Ranch ; 7 des Plopettes ; Atelier : 10 lignes, le titre, 7 lignes
				for tab, n in { ranch = 6, helpers = 7, workshop = 18 } do
					local sf = c.Up._list(tab)
					local shown = #c.Up._shown(tab)
					local heights = {}
					for _ = 1, n do
						table.insert(heights, 112)
					end
					expect(shown + (if tab == "workshop" then 1 else 0)).toBe(n)
					expect(sf.CanvasSize.Y.Offset).toBe(c.Up.canvasHeight(heights))
				end
				-- 4 lignes entières et 48 px de la 5e : 4 × 128 + 48 = 560
				expect(4 * U.Row.step + 48).toBe(U.Content.h)
				S.clean(c, expect)
			end
		)

		-- GDD v2.0 §10.7.5 : « Avant Pip (Record R 2), l'onglet est visible avec un cadenas « Record 2 » »
		-- (§10.7.6 : un état = un dessin ET un mot, jamais la couleur seule)
		it(
			"onglet Plopettes avant Pip : cadenas dessiné ET mot « Record 2 », lisibles, actif ou non ; après Pip : rien",
			function()
				local c = S.client({
					snap = S.snap(1, function(p)
						p.R = 1
						p.bestR = 1
					end),
				})
				local r = S.Balance.Helpers.ByRecordR[1]
				local issues = {}
				local function note(msg)
					table.insert(issues, msg)
				end
				local lockedW = nil
				for _, res in { Vector2.new(1280, 720), Vector2.new(1920, 1080), Vector2.new(3840, 2160) } do
					for _, lang in { "en", "fr" } do
						local tag = string.format("%dx%d %s", res.X, res.Y, lang)
						TvAudit.setResolution(c.h, res)
						TvAudit.setLanguage(c.h, lang)
						-- onglet Plopettes inactif (Ranch ouvert), puis actif
						for _, tab in { "ranch", "helpers" } do
							S.open(c, tab)
							Layout.apply(c.h)
							local b = c.Up._tab("helpers")
							lockedW = b.Size.X.Offset
							local box = Layout.rect(b)
							local lock = b:FindFirstChild("Lock")
							local word = b:FindFirstChild("LockWord")
							local label = b:FindFirstChild("Label")
							if
								lock == nil
								or word == nil
								or not Layout.visible(lock)
								or not Layout.visible(word)
							then
								note(tag .. " " .. tab .. " : cadenas ou mot absent de l'onglet Plopettes")
								continue
							end
							local want = S.Localization.get(lang, "upgrades.state.locked", { r = r })
							if word.Text ~= want then
								note(
									string.format(
										"%s : mot « %s » au lieu de « %s »",
										tag,
										word.Text,
										want
									)
								)
							end
							for _, part in { lock, word, label } do
								local pr = Layout.rect(part)
								if pr == nil or not inside(pr, box) then
									note(tag .. " " .. tab .. " : " .. part.Name .. " hors de l'onglet")
								end
							end
							-- de gauche à droite : libellé, cadenas, mot, sans chevauchement
							local lr, kr, wr = Layout.rect(label), Layout.rect(lock), Layout.rect(word)
							if lr.x + lr.w > kr.x + EPS or kr.x + kr.w > wr.x + EPS then
								note(tag .. " " .. tab .. " : libellé, cadenas et mot se chevauchent")
							end
							-- cadenas lisible sur le fond de l'onglet (anse et corps ; le trou de la serrure
							-- est un détail du corps)
							local bg = b.BackgroundColor3
							local body, bodyArea = nil, 0
							for _, d in lock:GetDescendants() do
								if d:IsA("Frame") and d.Visible then
									local stroke = d:FindFirstChildOfClass("UIStroke")
									if stroke and d.BackgroundTransparency >= 0.99 then
										if contrast(stroke.Color, bg) < 3 then
											note(
												string.format(
													"%s %s : anse du cadenas peu lisible (%.2f)",
													tag,
													tab,
													contrast(stroke.Color, bg)
												)
											)
										end
									elseif d.BackgroundTransparency < 0.5 then
										local area = d.Size.X.Scale * d.Size.Y.Scale
										if area > bodyArea then
											body, bodyArea = d, area
										end
									end
								end
							end
							if body == nil or contrast(body.BackgroundColor3, bg) < 3 then
								note(
									string.format(
										"%s %s : corps du cadenas peu lisible (%.2f)",
										tag,
										tab,
										if body then contrast(body.BackgroundColor3, bg) else 0
									)
								)
							end
							-- le mot : contraste avec le fond ou avec son contour sombre (≥ 3 ; contour actif
							-- sauf Enabled = false, comme Screens.contrastIssues)
							local ratio = contrast(word.TextColor3, bg)
							local ts = word:FindFirstChild("TextStroke")
							if ts and ts:IsA("UIStroke") and ts.Enabled ~= false then
								ratio = math.max(ratio, contrast(word.TextColor3, ts.Color))
							end
							if ratio < 3 then
								note(string.format("%s %s : mot peu lisible (%.2f)", tag, tab, ratio))
							end
							-- la rangée garde la place de L2 / R2 et Fermer à son bout (D5)
							local win = c.PC.window("Upgrades")
							local k = Layout.rect(win).w / 1440
							local close = Layout.rect(win:FindFirstChild("Body"):FindFirstChild("Close"))
							local last = Layout.rect(c.Up._tab("workshop"))
							if last.x + last.w > close.x - 2 * 56 * k then
								note(tag .. " : Fermer, L2 et R2 sans place au bout des onglets")
							end
						end
					end
				end
				-- après Pip (nouvel instantané, réouverture) : ni cadenas ni mot, l'onglet reprend sa largeur
				S.patch(
					c,
					S.snap(2, function(p)
						p.R = r
						p.bestR = r
					end)
				)
				c.PC.closeAll()
				TvAudit.tick(c.h, 1)
				S.open(c, "helpers")
				local b = c.Up._tab("helpers")
				expect(b:FindFirstChild("Lock").Visible).toBe(false)
				expect(b:FindFirstChild("LockWord").Visible).toBe(false)
				expect(b.Size.X.Offset < lockedW).toBe(true)
				expect(table.concat(issues, "\n")).toBe("")
				S.clean(c, expect)
			end
		)
	end)
end
