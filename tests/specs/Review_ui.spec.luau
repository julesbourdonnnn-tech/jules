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
--     et le profil de milieu de partie respecte la capacité des enclos (« 20 / 4 »).

local roblox = require("@lune/roblox")
local Screens = require("../harness/Screens")
local Layout = require("../harness/Layout")
local Props = require("../harness/EngineProps")

local function prop(obj, name)
	return Props.get(obj, name)
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

		-- bouclier débutant affiché : au moins « 1′ »
		Screens.ranchStub(c, "rush", { shield = true })
		pcall(c.HUD._refresh)
		Screens.frames(c, 4, 0.1)
		local minutes = nil
		local hudGui = c.h.localPlayer:FindFirstChildOfClass("PlayerGui"):FindFirstChild("HUD")
		local shieldHolder = hudGui and hudGui:FindFirstChild("shield", true)
		if shieldHolder then
			local m = shieldHolder:FindFirstChild("Minutes")
			minutes = m and m.Text
		end
		it("bouclier débutant affiché : jamais « 0′ »", function()
			expect(shieldHolder ~= nil and shieldHolder.Visible).toBe(true)
			expect(minutes ~= "0′").toBe(true)
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
end
