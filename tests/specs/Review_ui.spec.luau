--!nocheck
-- Review_ui (revue indépendante de l'interface, outil d'écrans tools/screens) : défauts vus à l'œil
-- sur les captures et que les contrôles automatiques ne voyaient pas. Chaque test échouait avant sa
-- correction (journal : scratchpad/v2/ecrans/revue.md).
--   * fenêtres opaques : un panneau (ou la carte du retour) ne laisse jamais transparaître le HUD et
--     le rail dessous (« GRAND SPLORCH ! » fantôme derrière les cases, les lignes et les badges) ;
--   * coins arrondis : un remplissage (jauge du Grand Splorch, balayage de Bondir) reste dans la
--     forme ronde de son cadre (ClipsDescendants de Roblox coupe au rectangle, jamais à l'arrondi :
--     seul un CanvasGroup arrondi coupe à l'arrondi) ;
--   * Guide du Squishydex : virgule décimale en français, et une chance non nulle n'est jamais
--     écrite « 0,0 % » ;
--   * bouclier débutant : jamais « 0′ » tant que l'indicateur est affiché ;
--   * scénarios de l'outil : chaque tenue de l'Aperçu existe (« crown » montrait le Pull douillet),
--     et le profil de milieu de partie respecte la capacité des enclos (« 20 / 4 ») ;
--   * cases vives (case choisie du Ranch, paliers de Nourris Plop, étapes de l'Accueil, espèce
--     complète, boutons dorés) : la couleur des lettres seule se lit sur le fond, le texte n'est
--     jamais un simple contour (« Taille 437 K » lavande sur vert : 1,08 sans le contour).

local roblox = require("@lune/roblox")
local Screens = require("../harness/Screens")
local Layout = require("../harness/Layout")
local Props = require("../harness/EngineProps")
local Gamepad = require("../harness/Gamepad")
local Enum = roblox.Enum

local function prop(obj, name)
	return Props.get(obj, name)
end

-- a → b de la part k (texte ou fond transparent mêlé à ce qui est dessous)
local function mixColor(a, b, k)
	return roblox.Color3.new(a.R + (b.R - a.R) * k, a.G + (b.G - a.G) * k, a.B + (b.B - a.B) * k)
end

local function shown(obj): boolean
	return Layout.visible(obj) and Layout.rect(obj) ~= nil
end

-- Rayon d'arrondi réel (px d'écran) d'un objet : UICorner (échelle × plus petit côté + décalage × k)
local function radiusOf(obj): number
	local corner = obj:FindFirstChildOfClass("UICorner")
	local r = Layout.rect(obj)
	if corner == nil or r == nil then
		return 0
	end
	local cr = prop(corner, "CornerRadius") or roblox.UDim.new(0, 8)
	local k = r.k or 1
	return math.min(math.min(r.w, r.h) / 2, cr.Scale * math.min(r.w, r.h) + cr.Offset * k)
end

-- Un fond plein (BackgroundTransparency < 0,5) qui porte du texte est-il partiellement transparent
-- par son UIGradient ? (le moteur applique Transparency du dégradé au fond : ce qui est dessous
-- transparaît)
local function seeThroughIssues(c)
	local out = {}
	local playerGui = c.h.localPlayer:FindFirstChildOfClass("PlayerGui")
	for _, obj in playerGui:GetDescendants() do
		if obj:IsA("GuiObject") and shown(obj) and (prop(obj, "BackgroundTransparency") or 0) < 0.5 then
			local grad = obj:FindFirstChildOfClass("UIGradient")
			local off = grad and prop(grad, "Offset")
			-- reflet qui passe (Offset animé, hors du cadre au repos) : effet voulu
			local moving = off ~= nil and (math.abs(off.X) > 0.01 or math.abs(off.Y) > 0.01)
			if grad and not moving and prop(grad, "Enabled") ~= false then
				local ts = prop(grad, "Transparency")
				local maxT = 0
				if ts then
					for _, kp in ts.Keypoints do
						maxT = math.max(maxT, kp.Value)
					end
				end
				local hasText = false
				for _, d in obj:GetDescendants() do
					if (d:IsA("TextLabel") or d:IsA("TextButton")) and shown(d) then
						hasText = true
						break
					end
				end
				if maxT > 0.001 and hasText and not obj:IsA("CanvasGroup") then
					table.insert(
						out,
						string.format(
							"%s : fond plein transparent à %d %% par son dégradé (le HUD dessous transparaît)",
							Layout.name(obj),
							math.floor(maxT * 100 + 0.5)
						)
					)
				end
			end
		end
	end
	table.sort(out)
	return out
end

-- Fond visible d'un enfant qui déborde d'un coin arrondi de son parent (aucun CanvasGroup arrondi
-- entre les deux) : le point du coin hors de l'arc (à 0,29 × r du coin, sur la diagonale) est peint
local function cornerIssues(c, rootName)
	local out = {}
	local playerGui = c.h.localPlayer:FindFirstChildOfClass("PlayerGui")
	local root = playerGui:FindFirstChild(rootName)
	if root == nil then
		return { "écran " .. rootName .. " introuvable" }
	end
	for _, obj in root:GetDescendants() do
		local parent = obj.Parent
		if
			obj:IsA("GuiObject")
			and parent
			and parent:IsA("GuiObject")
			and not parent:IsA("CanvasGroup")
			and shown(obj)
			and shown(parent)
			and (prop(obj, "BackgroundTransparency") or 0) < 0.9
		then
			local rp = radiusOf(parent)
			local a, p = Layout.rect(obj), Layout.rect(parent)
			-- même couleur que le fond sous le parent (croissant de lune) : le débord ne se voit pas
			local gp = parent.Parent
			local invisible = gp ~= nil
				and gp:IsA("GuiObject")
				and (prop(gp, "BackgroundTransparency") or 0) < 0.5
				and (function()
					local x, y = prop(obj, "BackgroundColor3"), prop(gp, "BackgroundColor3")
					return x ~= nil
						and y ~= nil
						and math.abs(x.R - y.R) + math.abs(x.G - y.G) + math.abs(x.B - y.B) < 24 / 255
				end)()
			if rp >= 6 and not invisible and a.w > 1 and a.h > 1 then
				local d = 0.29 * rp
				local corners = {
					{ p.x + d, p.y + d },
					{ p.x + p.w - d, p.y + d },
					{ p.x + d, p.y + p.h - d },
					{ p.x + p.w - d, p.y + p.h - d },
				}
				-- le point est-il peint par l'enfant (rectangle arrondi de rayon rc) ?
				local rc = radiusOf(obj)
				local function painted(x, y): boolean
					if
						not (x > a.x + 0.5 and x < a.x + a.w - 0.5 and y > a.y + 0.5 and y < a.y + a.h - 0.5)
					then
						return false
					end
					local cx = math.clamp(x, a.x + rc, a.x + a.w - rc)
					local cy = math.clamp(y, a.y + rc, a.y + a.h - rc)
					return (x - cx) ^ 2 + (y - cy) ^ 2 <= rc * rc
				end
				for _, pt in corners do
					local x, y = pt[1], pt[2]
					if painted(x, y) then
						table.insert(
							out,
							Layout.name(obj)
								.. " : fond carré dans le coin arrondi de "
								.. Layout.name(parent)
						)
						break
					end
				end
			end
		end
	end
	table.sort(out)
	return out
end
Screens.cornerIssues = cornerIssues
Screens.seeThroughIssues = seeThroughIssues

-- Cases d'une grille d'Objectifs (Nourris Plop, Accueil) : fond vif (vert « atteint », bleu
-- « prochain ») ; « Jour 1 » or, récompense blanche et ✓ vert s'y lisaient à 1,2, 1,8 et 1,0 sans le
-- contour (le ✓ vert sur vert n'était qu'un contour). Retourne { err, cells, bright, bad }
local function vividCellIssues(c, screen, pageName)
	local out = { err = "", cells = 0, bright = 0, bad = {} }
	if screen == nil then
		out.err = "écran introuvable"
		return out
	end
	local shownOk, err = Screens.show(c, screen)
	if not shownOk then
		out.err = tostring(err)
		return out
	end
	Screens.layout(c)
	local win = c.PC.window("Objectives")
	local page = win and win:FindFirstChild(pageName, true)
	for _, cell in (page and page:GetDescendants() or {}) do
		if cell:IsA("GuiButton") and shown(cell) then
			out.cells += 1
			local bg = cell.BackgroundColor3
			if Screens.contrast(roblox.Color3.new(1, 1, 1), bg) < 3 then
				out.bright += 1
			end
			for _, d in cell:GetChildren() do
				if d:IsA("TextLabel") and d.Text ~= "" and shown(d) then
					local ratio = Screens.contrast(d.TextColor3, bg)
					if ratio < 3 then
						table.insert(
							out.bad,
							string.format("%s « %s » : %.2f", Layout.name(d), d.Text, ratio)
						)
					end
					local stroke = d:FindFirstChildOfClass("UIStroke")
					if
						stroke
						and prop(stroke, "Enabled") ~= false
						and Screens.contrast(d.TextColor3, stroke.Color) < 1.5
					then
						table.insert(out.bad, Layout.name(d) .. " : contour de la couleur des lettres")
					end
				end
			end
		end
	end
	return out
end

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local profile = Screens.profileById("tv1080")

	describe("Revue UI › scénarios de l'outil d'écrans", function()
		it("chaque tenue de l'Aperçu de PANEL_TABS existe dans Config/Cosmetics", function()
			local h = Harness.new()
			local Cosmetics = h:require("ReplicatedStorage.Shared.Config.Cosmetics")
			local missing = {}
			for _, entry in Screens.PANEL_TABS do
				if entry[1] == "OutfitPreview" then
					for _, tab in entry[2] do
						if Cosmetics.ByKindId["outfit:" .. tab] == nil then
							table.insert(missing, tab)
						end
					end
				end
			end
			h:dispose()
			expect(table.concat(missing, ", ")).toBe("")
		end)

		it("profil de milieu de partie : pas plus de squishies dans les enclos que de places", function()
			local h = Harness.new()
			local Formulas = h:require("ReplicatedStorage.Shared.Logic.Formulas")
			for _, state in { "mid", "late" } do
				local p = Screens.profile(state)
				local inPens = 0
				for _, sq in p.squishies do
					if sq.at == "pen" then
						inPens += 1
					end
				end
				local tiles = p.tiles or {}
				local passes = p.passes or {}
				local cap = Formulas.penCapacity(tiles.pens or 0, passes.BigRanch == true)
				expect(state .. " : " .. inPens .. " / " .. cap .. (if inPens <= cap then "" else " (trop)")).toBe(
					state .. " : " .. inPens .. " / " .. cap
				)
			end
			h:dispose()
		end)
	end)

	describe("Revue UI › PS5 TV 1920 × 1080 › fr", function()
		local ok, c = pcall(Screens.boot, Harness, profile, "fr", "mid")
		if not ok then
			it("démarrage du client", function()
				error(c)
			end)
			return
		end

		-- chaque panneau (1er onglet) et la carte du retour : aucun fond plein à moitié transparent
		for _, entry in Screens.PANEL_TABS do
			local panel, tabs = entry[1], entry[2]
			local tab = if tabs[1] ~= "" then tabs[1] else nil
			Screens.unstub(c)
			Screens.open(c, panel, tab)
			Screens.layout(c)
			local issues = seeThroughIssues(c)
			it("panneau " .. panel .. " : fenêtre opaque (le HUD ne transparaît pas)", function()
				expect(table.concat(issues, "\n")).toBe("")
			end)
		end
		Screens.closeAll(c)

		-- Guide du Squishydex : au Grand Splorch I (Cuve de qualité 2 : Mythique 0,02 %)
		c.h:fireClient(Screens.REMOTES .. "DataPatch", { R = 1 }, {})
		Screens.frames(c, 3, 0.1)
		Screens.open(c, "Squishydex", "guide")
		Screens.layout(c)
		local lines = {}
		local win = c.PC.window("Squishydex")
		for _, d in (win and win:GetDescendants() or {}) do
			if d:IsA("TextLabel") and string.match(d.Name, "^Line%d+$") then
				table.insert(lines, d.Text)
			end
		end
		it("Guide : au moins une ligne de chance lue", function()
			expect(#lines > 10).toBe(true)
		end)
		it("Guide (fr) : virgule décimale, jamais un point (« 52,0 % », « ×1,5 »)", function()
			local bad = {}
			for _, text in lines do
				if string.find(text, "%d%.%d") then
					table.insert(bad, text)
				end
			end
			expect(table.concat(bad, " | ")).toBe("")
		end)
		it(
			"Guide : une chance non nulle n'est jamais écrite « 0,0 % » (Mythique à la qualité 2)",
			function()
				local Rarities = c.h:require("ReplicatedStorage.Shared.Config.Rarities")
				local mythic = c.Localization.get("fr", "rarity." .. Rarities.List[6].key)
				local found = nil
				for _, text in lines do
					if string.sub(text, 1, #mythic) == mythic then
						found = text
					end
				end
				expect(found ~= nil).toBe(true)
				expect(string.find(found, "0[,.]0 %%") == nil and string.find(found, "0[,.]0%s") == nil).toBe(
					true
				)
			end
		)
		Screens.closeAll(c)

		-- états « Équipé » (Ranch › Style) et « Complète ! » (Squishydex › Familles) : la couleur du
		-- texte elle-même se lit sur la case verte (vert sur vert : 1,9 sans le contour)
		local function statusContrast(panel, tab, wanted)
			Screens.open(c, panel, tab)
			local win = c.PC.window(panel)
			local out = {}
			local seen = 0
			for _, d in (win and win:GetDescendants() or {}) do
				if d:IsA("TextLabel") and d.Name == "Status" and d.Text == wanted and Layout.visible(d) then
					seen += 1
					local card = d.Parent
					while card and not card:IsA("GuiButton") do
						card = card.Parent
					end
					if card then
						local ratio = Screens.contrast(d.TextColor3, card.BackgroundColor3)
						if ratio < 3 then
							table.insert(out, string.format("%s : %.2f", Layout.name(d), ratio))
						end
					end
				end
			end
			return seen, out
		end
		local seenEq, badEq =
			statusContrast("Ranch", "style", c.Localization.get("fr", "panel.ranch.style.equipped"))
		it("Ranch › Style : « Équipé » lisible sur sa case (contraste du texte seul ≥ 3)", function()
			expect(seenEq >= 1).toBe(true)
			expect(table.concat(badEq, " | ")).toBe("")
		end)
		local seenFam, badFam =
			statusContrast("Squishydex", "families", c.Localization.get("fr", "panel.dex.familyComplete"))
		it(
			"Squishydex › Familles : « Complète ! » lisible sur sa rangée (contraste du texte seul ≥ 3)",
			function()
				expect(seenFam >= 1).toBe(true)
				expect(table.concat(badFam, " | ")).toBe("")
			end
		)
		Screens.closeAll(c)

		-- carte du retour
		for _, group in Screens.groups() do
			if group.id == "mid" then
				for _, screen in Screens.expand(c, group) do
					if screen.id == "return.ready" then
						Screens.show(c, screen)
						Screens.layout(c)
						local issues = seeThroughIssues(c)
						it("carte du retour : opaque", function()
							expect(table.concat(issues, "\n")).toBe("")
						end)
					end
				end
			end
		end
		Screens.closeAll(c)
		Screens.flushAll(c)

		-- HUD : jauge du Grand Splorch pleine (prêt) et Bondir en recharge
		c.Chase.cooldownLeft = function()
			return 2
		end
		pcall(c.HUD._refresh)
		Screens.frames(c, 4, 0.1)
		Screens.layout(c)
		local hudCorners = cornerIssues(c, "HUD")
		it("HUD : aucun remplissage carré dans un cadre rond (jauge du Grand Splorch, Bondir)", function()
			expect(table.concat(hudCorners, "\n")).toBe("")
		end)

		-- bouclier débutant affiché : au moins « 1 » et sa marque des minutes DESSINÉE (« ′ » hors police,
		-- règle 18 ; lot B2, D20, journal B2-47 : le texte n'est plus que le nombre)
		Screens.ranchStub(c, "rush", { shield = true })
		pcall(c.HUD._refresh)
		Screens.frames(c, 4, 0.1)
		local minutes = nil
		local prime = nil
		local hudGui = c.h.localPlayer:FindFirstChildOfClass("PlayerGui"):FindFirstChild("HUD")
		local shieldHolder = hudGui and hudGui:FindFirstChild("shield", true)
		if shieldHolder then
			local m = shieldHolder:FindFirstChild("Minutes")
			minutes = m and m.Text
			prime = shieldHolder:FindFirstChild("Prime")
		end
		it(
			"bouclier débutant affiché : jamais « 0 » (au moins 1 minute), marque des minutes dessinée",
			function()
				expect(shieldHolder ~= nil and shieldHolder.Visible).toBe(true)
				expect(type(minutes) == "string" and string.match(minutes, "^%d+$") ~= nil).toBe(true)
				expect(tonumber(minutes) >= 1).toBe(true)
				expect(prime ~= nil and prime.Visible and prime:GetAttribute("Icon") == "prime").toBe(true)
			end
		)
		Harness.disposeAll()
	end)

	-- Réglages : la liste ne coupe jamais une ligne de texte en deux, ni en haut ni en bas, à aucune
	-- position de défilement (rangée entrouverte « peek » de l'outil : la description de la 6e
	-- rangée tranchée à mi-hauteur au départ, son titre en fin de liste)
	describe("Revue UI › Réglages : aucune ligne de texte tranchée", function()
		local ok, c = pcall(Screens.boot, Harness, profile, "fr", "mid")
		if not ok then
			it("démarrage du client", function()
				error(c)
			end)
			return
		end
		Screens.open(c, "Settings")
		local function sliced(step: number): { string }
			Screens.layout(c)
			local win = c.PC.window("Settings")
			local list = win and win:FindFirstChild("List", true)
			local out = {}
			local box = list and Layout.rect(list)
			if box == nil then
				return { "liste introuvable" }
			end
			for _, d in list:GetDescendants() do
				if d:IsA("TextLabel") and d.Text ~= "" and Layout.visible(d) then
					local r = Layout.rect(d)
					if r then
						local top = math.max(r.y, box.y)
						local bottom = math.min(r.y + r.h, box.y + box.h)
						local shownH = bottom - top
						-- une boîte de texte entamée de plus de 4 px (la ligne d'encre l'est aussi)
						if shownH > 0 and shownH < r.h - 4 then
							table.insert(
								out,
								string.format("pas %d : %s (%d / %d px)", step, d.Text, shownH, r.h)
							)
						end
					end
				end
			end
			return out
		end
		local bad = sliced(0)
		for step = 1, 12 do
			Gamepad.tap(c.h, Enum.KeyCode.DPadDown)
			Screens.frames(c, 4, 0.2)
			for _, line in sliced(step) do
				table.insert(bad, line)
			end
		end
		it("au départ, en descendant et en bout de liste", function()
			expect(table.concat(bad, "\n")).toBe("")
		end)
		Harness.disposeAll()
	end)

	-- message (toast) pendant qu'un panneau est ouvert : jamais sur les onglets ni le contenu du
	-- panneau (type « covered » de l'outil ; il cachait les onglets pendant 3 s)
	for _, pid in { "tv1080", "tv720" } do
		describe("Revue UI › message sur un panneau ouvert › " .. pid, function()
			local ok, c = pcall(Screens.boot, Harness, Screens.profileById(pid), "fr", "mid")
			if not ok then
				it("démarrage du client", function()
					error(c)
				end)
				return
			end
			local function overlaps(a, b): boolean
				return a.x < b.x + b.w - 1
					and b.x < a.x + a.w - 1
					and a.y < b.y + b.h - 1
					and b.y < a.y + a.h - 1
			end
			local function check(label: string, before: boolean)
				local win = c.PC.window("Ranch")
				local playerGui = c.h.localPlayer:FindFirstChildOfClass("PlayerGui")
				local stack = playerGui:FindFirstChild("Toasts")
				stack = stack and stack:FindFirstChild("Stack", true)
				local bad = {}
				local count = 0
				for _, t in (stack and stack:GetChildren() or {}) do
					if t.Name == "Toast" and shown(t) then
						count += 1
						local r = Layout.rect(t)
						local body = win and win:FindFirstChild("Body")
						for _, part in (body and body:GetChildren() or {}) do
							if part:IsA("GuiObject") and shown(part) and overlaps(r, Layout.rect(part)) then
								table.insert(bad, Layout.name(part))
							end
						end
					end
				end
				it(label, function()
					expect(count >= 1).toBe(true)
					expect(table.concat(bad, ", ")).toBe("")
				end)
				return before
			end
			-- toast montré panneau déjà ouvert
			Screens.open(c, "Ranch", "pens")
			-- Roblox tient AbsoluteSize à jour à chaque image ; le harnais, seulement à Layout.apply
			Screens.layout(c)
			c.Toast.show("Rien à ranger", "info")
			Screens.frames(c, 2, 0.05)
			Screens.layout(c)
			check("toast montré panneau ouvert : hors des onglets et du contenu", false)
			-- toast montré AVANT l'ouverture du panneau (il était sous les bannières)
			Screens.closeAll(c)
			Screens.frames(c, 40, 0.1)
			c.Toast.show("Enclos pleins", "warning")
			Screens.frames(c, 1, 0.05)
			c.PC.open("Ranch", "pens")
			Screens.frames(c, 3, 0.05)
			Screens.layout(c)
			check("toast déjà là à l'ouverture : il monte dans la barre de titre", true)
			Harness.disposeAll()
		end)
	end

	-- texte d'un écran dessiné dessous tranché par le bord d'une fenêtre opaque (type « occluded » de
	-- l'outil) : la pastille des pièces (« 1,2… M ») et le suivi du Grand Splorch coupés par le haut
	-- du panneau, les libellés du rail (« Gra », « Ran », « Squ ») par son bord gauche, la puce
	-- « GRAND SPLORCH ! » par le bas de la carte du choix Rush / Cozy. Caché entier ou entier visible,
	-- jamais à moitié.
	local function guiOf(obj)
		local p = obj
		while p and not p:IsA("ScreenGui") do
			p = p.Parent
		end
		return p
	end
	local function slicedUnder(c, cover): { string }
		local out = {}
		local coverRect = Layout.rect(cover)
		local coverGui = guiOf(cover)
		if coverRect == nil or coverGui == nil then
			return { "fenêtre introuvable" }
		end
		local order = prop(coverGui, "DisplayOrder") or 0
		local playerGui = c.h.localPlayer:FindFirstChildOfClass("PlayerGui")
		for _, d in playerGui:GetDescendants() do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and shown(d) then
				local g = guiOf(d)
				if g and g ~= coverGui and (prop(g, "DisplayOrder") or 0) < order then
					local r = Layout.rect(d)
					local w = math.min(r.x + r.w, coverRect.x + coverRect.w) - math.max(r.x, coverRect.x)
					local hh = math.min(r.y + r.h, coverRect.y + coverRect.h) - math.max(r.y, coverRect.y)
					local frac = if w > 0 and hh > 0 and r.w * r.h > 0 then (w * hh) / (r.w * r.h) else 0
					if frac > 0.08 and frac < 0.92 then
						table.insert(
							out,
							string.format(
								"%s « %s » coupé à %d %%",
								Layout.name(d),
								d.Text,
								math.floor(frac * 100)
							)
						)
					end
				end
			end
		end
		table.sort(out)
		return out
	end
	for _, pid in { "tv1080", "tv720", "tv2160" } do
		describe("Revue UI › aucun texte tranché par la fenêtre au-dessus › " .. pid, function()
			local ok, c = pcall(Screens.boot, Harness, Screens.profileById(pid), "fr", "mid")
			if not ok then
				it("démarrage du client", function()
					error(c)
				end)
				return
			end
			-- écrans de l'outil (groupe « mid ») : chaque panneau à son 1er onglet, Diagnostics compris
			-- (son instantané du serveur est envoyé par le scénario)
			local byId = {}
			for _, group in Screens.groups() do
				for _, s in group.screens do
					if byId[s.id] == nil then
						byId[s.id] = s
					end
				end
			end
			for _, entry in Screens.PANEL_TABS do
				local panel, tabs = entry[1], entry[2]
				local id = "panel." .. panel .. (if tabs[1] ~= "" then "." .. tabs[1] else "")
				local shownOk, err = Screens.show(c, byId[id])
				Screens.frames(c, 3, 0.1)
				Screens.layout(c)
				local bad = if shownOk then slicedUnder(c, c.PC.window(panel)) else { tostring(err) }
				it(
					"panneau " .. panel .. " : HUD et rail dessous cachés entiers ou entiers visibles",
					function()
						expect(table.concat(bad, "\n")).toBe("")
					end
				)
			end
			Screens.closeAll(c)
			Screens.frames(c, 3, 0.1)
			Screens.layout(c)
			-- rail fermé, aucun panneau : le HUD revient entier (pièces, suivi, pastille d'événement)
			local back = {}
			for _, name in { "coins", "goalTracker" } do
				if not c.HUD.visible(name) then
					table.insert(back, name)
				end
			end
			it("panneau fermé : pièces et suivi du Grand Splorch de retour", function()
				expect(table.concat(back, ", ")).toBe("")
			end)
			-- carte bloquante du choix Rush / Cozy
			local shownOk, err = Screens.show(c, byId["card.mode"])
			Screens.layout(c)
			local bad = if shownOk then slicedUnder(c, c.Cards.frame("mode")) else { tostring(err) }
			it(
				"carte du choix Rush / Cozy : puce et HUD dessous cachés entiers ou entiers visibles",
				function()
					expect(table.concat(bad, "\n")).toBe("")
				end
			)
			Harness.disposeAll()
		end)
	end

	-- voiles des panneaux, de la carte du choix et de l'écran de retour : tout l'écran, bande de la
	-- barre de Roblox comprise (l'écran commence sous elle, GuiInset 58 px : une bande claire non
	-- voilée restait en haut de chaque panneau et de chaque carte bloquante)
	describe("Revue UI › voiles plein écran (bande de la barre de Roblox comprise)", function()
		local ok, c = pcall(Screens.boot, Harness, profile, "fr", "mid")
		if not ok then
			it("démarrage du client", function()
				error(c)
			end)
			return
		end
		local byId = {}
		for _, group in Screens.groups() do
			for _, s in group.screens do
				if byId[s.id] == nil then
					byId[s.id] = s
				end
			end
		end
		local vh = profile.h
		local function veilOf(guiName: string): string
			local playerGui = c.h.localPlayer:FindFirstChildOfClass("PlayerGui")
			local gui = playerGui:FindFirstChild(guiName)
			local veil = gui and gui:FindFirstChild("Veil")
			if veil == nil or not shown(veil) then
				return guiName .. " : voile absent ou caché"
			end
			local r = Layout.rect(veil)
			-- partie visible du voile (l'écran va de 0 à vh)
			return string.format(
				"%s : y %d à %d",
				guiName,
				math.floor(math.max(r.y, 0) + 0.5),
				math.floor(math.min(r.y + r.h, vh) + 0.5)
			)
		end
		local function expected(guiName: string): string
			return string.format("%s : y 0 à %d", guiName, vh)
		end
		local cases = {
			{ "Panels", "panel.Ranch.pens" },
			{ "Cards", "card.mode" },
			{ "Return", "return.plain" },
		}
		for _, case in cases do
			local guiName, id = case[1], case[2]
			local shownOk, err = Screens.show(c, byId[id])
			Screens.layout(c)
			local got = if shownOk then veilOf(guiName) else tostring(err)
			it(id .. " : le voile couvre tout l'écran", function()
				expect(got).toBe(expected(guiName))
			end)
		end
		Harness.disposeAll()
	end)

	-- texte dont le contour (UIStroke Contextual) est de la même couleur que les lettres : les
	-- lettres se fondent en une tache (« ×2 » du bonus du HUD, bleu nuit sur contour bleu nuit, lu
	-- comme un nuage noir sur la pastille dorée)
	describe("Revue UI › aucun texte fondu dans son contour de même couleur", function()
		local ok, c = pcall(Screens.boot, Harness, profile, "fr", "mid")
		if not ok then
			it("démarrage du client", function()
				error(c)
			end)
			return
		end
		local byId = {}
		local order = {}
		for _, group in Screens.groups() do
			if group.state == "mid" and group.id ~= "huge" then
				for _, s in Screens.expand(c, group) do
					if byId[s.id] == nil then
						byId[s.id] = s
						table.insert(order, s.id)
					end
				end
			end
		end
		local function close(a, b): boolean
			return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 0.12
		end
		local bad = {}
		local seen = {}
		for _, id in order do
			local shownOk = Screens.show(c, byId[id])
			if shownOk then
				Screens.layout(c)
				local playerGui = c.h.localPlayer:FindFirstChildOfClass("PlayerGui")
				for _, d in playerGui:GetDescendants() do
					if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and shown(d) then
						local stroke = d:FindFirstChildOfClass("UIStroke")
						if
							stroke
							and prop(stroke, "Enabled") ~= false
							and prop(stroke, "ApplyStrokeMode") ~= Enum.ApplyStrokeMode.Border
							and (prop(stroke, "Transparency") or 0) < 0.5
							and (prop(stroke, "Thickness") or 0) >= 1.5
							and close(prop(d, "TextColor3"), prop(stroke, "Color"))
						then
							local key = Layout.name(d)
							if not seen[key] then
								seen[key] = true
								table.insert(bad, string.format("%s « %s » (%s)", key, d.Text, id))
							end
						end
					end
				end
			end
		end
		table.sort(bad)
		it(
			"chaque écran de milieu de partie (HUD, panneaux, cartes, bannières) : contour d'une autre couleur que le texte",
			function()
				expect(#order > 5).toBe(true)
				expect(table.concat(bad, "\n")).toBe("")
			end
		)
		Harness.disposeAll()
	end)

	-- case choisie du Ranch (Vendre / Relâcher, Fusionner « Choisir B ») : fond vert vif ; nom
	-- blanc, « Taille » lavande et « Doré » or s'y lisaient à 1,8, 1,1 et 1,2 de contraste sans le
	-- contour (« Taille 437K » presque invisible à 3 m). La couleur des lettres elle-même doit se lire
	describe(
		"Revue UI › cases vives (case choisie du Ranch, paliers de Nourris Plop) : textes lisibles",
		function()
			local ok, c = pcall(Screens.boot, Harness, profile, "fr", "mid")
			if not ok then
				it("démarrage du client", function()
					error(c)
				end)
				return
			end
			local byId = {}
			for _, group in Screens.groups() do
				if group.state == "mid" and group.id ~= "huge" then
					for _, s in Screens.expand(c, group) do
						if byId[s.id] == nil then
							byId[s.id] = s
						end
					end
				end
			end
			for _, id in { "panel.Ranch.sell.confirm", "panel.Ranch.fuse.chooseB" } do
				local shownOk, err = Screens.show(c, byId[id])
				Screens.layout(c)
				local picked = 0
				local bad = {}
				local win = c.PC.window("Ranch")
				for _, cell in (win and win:GetDescendants() or {}) do
					local check = cell:IsA("GuiButton") and cell:FindFirstChild("Check")
					if check and shown(cell) and shown(check) then
						picked += 1
						for _, name in { "Name", "Size", "Line" } do
							local d = cell:FindFirstChild(name)
							if d and d:IsA("TextLabel") and d.Text ~= "" and shown(d) then
								local ratio = Screens.contrast(d.TextColor3, cell.BackgroundColor3)
								if ratio < 3 then
									table.insert(
										bad,
										string.format("%s « %s » : %.2f", Layout.name(d), d.Text, ratio)
									)
								end
								-- lettres sombres sur le vert : jamais cernées d'un contour de leur couleur
								local stroke = d:FindFirstChildOfClass("UIStroke")
								if
									stroke
									and prop(stroke, "Enabled") ~= false
									and Screens.contrast(d.TextColor3, stroke.Color) < 1.5
								then
									table.insert(
										bad,
										Layout.name(d) .. " : contour de la couleur des lettres"
									)
								end
							end
						end
					end
				end
				it(id .. " : textes de la case choisie lisibles (contraste du texte seul ≥ 3)", function()
					expect(if shownOk then "" else tostring(err)).toBe("")
					expect(picked >= 1).toBe(true)
					expect(table.concat(bad, "\n")).toBe("")
				end)
			end

			-- Objectifs › Nourris Plop (palier atteint vert vif, prochain palier bleu vif)
			local plop = vividCellIssues(c, byId["panel.Objectives.plop"], "Page_plop")
			it(
				"panel.Objectives.plop : textes des cases vives (atteint, prochain) lisibles (contraste du texte seul ≥ 3)",
				function()
					expect(plop.err).toBe("")
					expect(plop.cells >= 6).toBe(true)
					expect(plop.bright >= 1).toBe(true)
					expect(table.concat(plop.bad, "\n")).toBe("")
				end
			)
			Harness.disposeAll()
		end
	)

	-- Objectifs › Accueil à mi-parcours (nouveau joueur) : étapes faites en vert vif
	describe("Revue UI › Accueil : textes lisibles sur les étapes faites", function()
		local ok, c = pcall(Screens.boot, Harness, profile, "fr", "new")
		if not ok then
			it("démarrage du client", function()
				error(c)
			end)
			return
		end
		local screen = nil
		for _, group in Screens.groups() do
			if group.id == "new" then
				for _, s in group.screens do
					if s.id == "panel.Objectives.onboarding.partial" then
						screen = s
					end
				end
			end
		end
		local got = vividCellIssues(c, screen, "Page_onboarding")
		it(
			"panel.Objectives.onboarding.partial : textes des étapes faites lisibles (contraste du texte seul ≥ 3)",
			function()
				expect(got.err).toBe("")
				expect(got.cells >= 6).toBe(true)
				expect(got.bright >= 1).toBe(true)
				expect(table.concat(got.bad, "\n")).toBe("")
			end
		)
		Harness.disposeAll()
	end)

	-- Tout texte de milieu de partie : la couleur des lettres seule (sans le contour) se distingue de
	-- son fond plein le plus proche (contraste ≥ 1,5). Plus bas, le texte n'est plus qu'un contour :
	-- « 9 / 9 » lavande et nom blanc sur la case dorée d'une espèce complète (1,3 et 1,46), « Vendre »
	-- et « Meilleur Ami 1 » blancs sur l'or (1,46). Le style maison (blanc cerné sur vert, 1,76) passe
	describe("Revue UI › couleur du texte seule distincte de son fond (≥ 1,5)", function()
		local ok, c = pcall(Screens.boot, Harness, profile, "fr", "mid")
		if not ok then
			it("démarrage du client", function()
				error(c)
			end)
			return
		end
		local byId = {}
		local order = {}
		for _, group in Screens.groups() do
			if group.state == "mid" and group.id ~= "huge" then
				for _, s in Screens.expand(c, group) do
					if byId[s.id] == nil then
						byId[s.id] = s
						table.insert(order, s.id)
					end
				end
			end
		end
		local function decorative(d): boolean
			local cur = d
			while cur and cur:IsA("GuiObject") do
				if cur:GetAttribute("Decorative") == true then
					return true
				end
				cur = cur.Parent
			end
			return false
		end
		local function solidBehind(d)
			local cur = d
			while cur and cur:IsA("GuiObject") do
				if (prop(cur, "BackgroundTransparency") or 1) < 0.5 then
					return cur
				end
				cur = cur.Parent
			end
			return nil
		end
		local bad = {}
		local seen = {}
		local checked = 0
		for _, id in order do
			if Screens.show(c, byId[id]) then
				Screens.layout(c)
				local playerGui = c.h.localPlayer:FindFirstChildOfClass("PlayerGui")
				for _, d in playerGui:GetDescendants() do
					if
						(d:IsA("TextLabel") or d:IsA("TextButton"))
						and d.Text ~= ""
						-- icônes en texte (✓ ★ ♥ ✦…) : formes, pas des mots
						and string.find(d.Text, "[%w]") ~= nil
						and shown(d)
						and (prop(d, "TextTransparency") or 0) < 0.5
						and not decorative(d)
					then
						local back = solidBehind(d)
						if back then
							checked += 1
							-- fond à demi transparent (bouton grisé à 35 %) : mêlé au fond plein dessous
							local color = prop(back, "BackgroundColor3")
							local bt = prop(back, "BackgroundTransparency") or 0
							if bt > 0.01 then
								local under = solidBehind(back.Parent)
								color = mixColor(
									color,
									if under
										then prop(under, "BackgroundColor3")
										else roblox.Color3.new(0, 0, 0),
									bt
								)
							end
							local ink =
								mixColor(prop(d, "TextColor3"), color, prop(d, "TextTransparency") or 0)
							local ratio = Screens.contrast(ink, color)
							local key = string.gsub(Layout.name(d), "%d+", "#")
							if ratio < 1.5 and not seen[key] then
								seen[key] = true
								table.insert(
									bad,
									string.format("%s « %s » : %.2f (%s)", key, d.Text, ratio, id)
								)
							end
						end
					end
				end
			end
		end
		table.sort(bad)
		-- « Vendre » grisé (rien de choisi : bouton à 35 % de transparence, texte à 45 %) : l'or pâli
		-- par le panneau dessous ; des lettres bleu nuit sans contour n'y lisaient qu'à 2,65 (outil
		-- d'écrans) : grisé, le bouton garde le blanc cerné
		local sellGrey = "écran introuvable"
		if Screens.show(c, byId["panel.Ranch.sell"]) then
			Screens.layout(c)
			local win = c.PC.window("Ranch")
			local sellBtn = win and win:FindFirstChild("Sell", true)
			local label = sellBtn and sellBtn:FindFirstChild("Label")
			if label == nil then
				sellGrey = "bouton Vendre introuvable"
			else
				local t = prop(sellBtn, "BackgroundTransparency") or 0
				local panelBack = solidBehind(sellBtn.Parent)
				local under = if panelBack
					then prop(panelBack, "BackgroundColor3")
					else roblox.Color3.new(0, 0, 0)
				local gold = prop(sellBtn, "BackgroundColor3")
				local function mixc(a, b, k)
					return roblox.Color3.new(
						a.R + (b.R - a.R) * k,
						a.G + (b.G - a.G) * k,
						a.B + (b.B - a.B) * k
					)
				end
				local back = mixc(gold, under, t)
				local ink = mixc(prop(label, "TextColor3"), back, prop(label, "TextTransparency") or 0)
				local ratio = Screens.contrast(ink, back)
				local stroke = label:FindFirstChildOfClass("UIStroke")
				if stroke and prop(stroke, "Enabled") ~= false then
					ratio = math.max(ratio, Screens.contrast(ink, prop(stroke, "Color")))
				end
				sellGrey = if t > 0.1 and ratio < 3
					then string.format("« %s » grisé : %.2f", label.Text, ratio)
					elseif t <= 0.1 then "bouton Vendre non grisé (rien de choisi)"
					else ""
			end
		end
		it(
			"Ranch › Vendre grisé (rien de choisi) : « Vendre » lisible (contraste ≥ 3, contour compris)",
			function()
				expect(sellGrey).toBe("")
			end
		)
		it(
			"chaque écran de milieu de partie : couleur des lettres seule ≥ 1,5 sur son fond plein",
			function()
				expect(checked > 100).toBe(true)
				expect(table.concat(bad, "\n")).toBe("")
			end
		)
		Harness.disposeAll()
	end)
end
