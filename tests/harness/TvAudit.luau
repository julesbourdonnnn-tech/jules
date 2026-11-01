--!nocheck
-- TvAudit (paquet client-panels ; couche d du GDD §12.10, docs/04 §17.1 d) : audit « télé » du VRAI
-- client sur les écrans réels, bâti sur tests/harness/Layout et tests/harness/Gamepad.
--
--   local h = TvAudit.client({ profile = { coins = 5000 }, viewport = Vector2.new(3840, 2160) })
--   local report = TvAudit.walk(h)            -- parcours à 3 touches (croix, ✕, ○) depuis le menu
--   expect(table.concat(report.issues, "\n")).toBe("")
--   local all = TvAudit.run(h, { resolutions = Layout.TestResolutions, langs = { "en", "fr" } })
--
-- Contrôles (chaque fonction rend une liste de messages ; vide = conforme) :
--   overlaps(h, root)          textes et objets sélectionnables visibles qui se recouvrent (aucun
--                              n'étant l'ancêtre de l'autre ; objets coupés par un cadre ignorés)
--   clipped(h, root)           texte coupé ou sous 28 px TV (estimation de Gamepad.audit : largeur par
--                              classe de caractère, TextScaled, retours à la ligne — approximation
--                              documentée du moteur, docs/04 §17.3)
--   outsideSafe(h, root)       objet sélectionnable ou texte hors de la zone sûre de 5 %
--   glyphs(h, root)            glyphe non PlayStation sur console, lettre de bouton Xbox écrite
--   boundBehindWindow(h)       touche du jeu encore liée (ContextActionService) derrière une fenêtre
--   selection(h)               sélection vide ou hors de la fenêtre active (fenêtre ouverte), ou posée
--                              en jeu (aucune fenêtre)
--   escapes(h)                 objets atteints à la croix HORS de la fenêtre active
-- walk(h, opts) : depuis le jeu, ouvre le menu (croix ↓, liée par InputController ; repli :
-- PanelController.toggleMenu tant qu'InputController n'est pas livré), puis explore chaque écran
-- atteignable : objets atteints à la croix depuis la sélection (Layout.reachable), ✕ sur ceux qui
-- mènent à un autre écran (attributs TvNav, TvTab posés par l'UI). À chaque nouvel écran : tous les
-- contrôles ci-dessus ; puis ○ doit ramener à l'écran d'origine (sauf un onglet, dont ○ remonte au
-- menu), et ○ répété doit toujours rendre la main au jeu. Rend { screens, issues, edges }.
-- run(h, { resolutions, langs }) : walk à chaque résolution et dans chaque langue.

local roblox = require("@lune/roblox")
local Harness = require("./Harness")
local Layout = require("./Layout")
local Gamepad = require("./Gamepad")
local MockInstance = require("./MockInstance")

local Enum = roblox.Enum
local Vector2 = roblox.Vector2

local TvAudit = {}

TvAudit.CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
local CLIENT = TvAudit.CLIENT

-- Actions de fenêtre permises derrière une fenêtre (les touches du jeu, elles, doivent être déliées)
TvAudit.UI_ACTIONS = { FocusGuardBack = true, PanelTabs = true, PanelCycle = true, PanelScroll = true }
local MENU_KEYS = { ButtonY = true, DPadDown = true, M = true, Semicolon = true }
local GAME_KEYS = {
	ButtonX = true,
	ButtonB = true,
	ButtonR2 = true,
	ButtonL2 = true,
	ButtonL1 = true,
	ButtonR1 = true,
	DPadUp = true,
	DPadLeft = true,
	DPadRight = true,
	E = true,
	Q = true,
	R = true,
	F = true,
	LeftShift = true,
	One = true,
	Two = true,
	Three = true,
}

-- =============================================================================================
-- Client de test
-- =============================================================================================

local defaultsCache = nil

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

-- Profil par défaut du schéma v1 (Server/Data/Schema.defaults(), lu une fois dans un harnais serveur
-- créé AVANT le client : les crochets globaux de MockInstance vont au harnais créé en dernier)
function TvAudit.defaults()
	if defaultsCache == nil then
		local hs = Harness.new({ mode = "server" })
		defaultsCache = hs:require("ServerScriptService.Server.Data.Schema").defaults()
		hs:dispose()
	end
	return deepCopy(defaultsCache)
end

-- Ligne de squishy (Types.SquishyRecord)
function TvAudit.squishy(s, opts)
	opts = opts or {}
	return {
		s = s,
		m = opts.m or 0,
		st = opts.st or 0,
		z = opts.z or 100,
		zg = opts.zg or 0,
		bf = opts.bf or 0,
		lk = opts.lk == true,
		o = opts.o or "",
		at = opts.at or "pen",
		b = opts.b or 0,
		gd = 0,
	}
end

-- Client console (PS5 sur télé par défaut) démarré, profil reçu ; profil = défauts du schéma
-- complétés par opts.profile (fusion de premier niveau)
function TvAudit.client(opts)
	opts = opts or {}
	local profile = TvAudit.defaults()
	profile.receipts, profile.codes, profile.flags = nil, nil, nil -- clés privées
	for k, v in opts.profile or {} do
		profile[k] = v
	end
	if opts.lang then
		profile.settings.lang = opts.lang
	end
	local h = Harness.new({
		mode = "client",
		console = opts.console ~= false,
		viewport = opts.viewport,
		isStudio = opts.isStudio,
	})
	h:createRemotes()
	if opts.before then
		opts.before(h)
	end
	h:boot()
	local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
	Clock.freeze(opts.now or 1800000000)
	h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", profile)
	h:settle(3)
	return h
end

-- Intentions envoyées au serveur sur un remote (liste des arguments de chaque FireServer)
function TvAudit.sent(h, remote)
	local out = {}
	for _, e in h.log.serverEvents do
		if e.remote == remote then
			table.insert(out, e.args)
		end
	end
	return out
end

-- Boutique en vente (identifiants non nuls) : à passer en opts.before de TvAudit.client
function TvAudit.enableShop(h)
	local M = h:require("ReplicatedStorage.Shared.Config.Monetization")
	local n = 1000
	for _, key in { "AutoPot", "DoubleCoins", "BigRanch", "SaddlesTrails", "SeasonPass" } do
		n += 1
		M.Passes[key].id = n
	end
	for _, key in { "SquishParty", "CoinsSmall", "CoinsBig", "OutfitSweater", "OutfitCrown", "OutfitWinter" } do
		n += 1
		M.Products[key].id = n
	end
end

-- Profil riche (30 squishies en enclos, Dodo et Lettres, Squishydex à moitié tamponné, objectifs,
-- Boutique ouverte après 10 min, tenues) : pour parcourir tous les écrans avec du contenu
function TvAudit.richProfile(now)
	local t = now or 1800000000
	local sq = {}
	for i = 1, 30 do
		local s = ((i - 1) % 26) + 1
		sq["u" .. i] = TvAudit.squishy(s, {
			z = 1000 * i,
			m = if i % 10 == 0 then 4 else 0,
			st = i % 3,
			lk = i == 3,
			bf = if i == 1 then 1 else 0,
			at = if i <= 20 then "pen" elseif i <= 26 then "dodo" else "mail",
		})
	end
	local mut, stars = {}, {}
	for s = 1, 26 do
		mut[s] = if s % 2 == 0 then 0x3FF else 1
		stars[s] = s % 32
	end
	local day = math.floor(t / 86400)
	local defaults = TvAudit.defaults()
	local stats = defaults.stats
	stats.playSeconds = 9999
	return {
		squishies = sq,
		coins = 123456789,
		pot = 5000,
		R = 3,
		growth = { G = 20000, g = 1, t = t },
		stats = stats,
		dex = { mut = mut, stars = stars, fam = { 1, 0, 0, 0, 0, 0, 0 }, rewards = 0 },
		objectives = {
			day = day,
			list = {
				{ id = 1, p = 30, done = true, claimed = false },
				{ id = 7, p = 1, done = false, claimed = false },
				{ id = 14, p = 0, done = false, claimed = false },
			},
			rerolls = 0,
			allClaimed = false,
		},
		plopDays = 12,
		outfits = { owned = { plopBib = 1, sweater = 2 }, worn = {} },
		biggestEver = 2e6,
	}
end

-- Module du client
function TvAudit.mod(h, path)
	return h:require(CLIENT .. path)
end

-- Avance l'horloge du jeu (gardes de 0,35 s, maintiens) et une image
function TvAudit.tick(h, dt)
	local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
	if Clock.isFrozen() then
		Clock.advance(dt or 0.5)
	end
	h:step(1 / 60, 1)
	h:settle(1)
end

-- Écran simulé (px) : caméra, échelle de UI/Root recalculée
function TvAudit.setResolution(h, size)
	h.viewport = size
	MockInstance.screenSize = size
	local camera = h.game.Workspace.CurrentCamera
	if camera then
		camera.ViewportSize = size
	end
	h:settle(2)
end

-- Langue du jeu (réglage « Langue » du profil répliqué)
function TvAudit.setLanguage(h, lang)
	local State = h:require(CLIENT .. "Controllers.StateController")
	local settings = table.clone(State.get("settings") or {})
	settings.lang = lang
	h:fireClient("ReplicatedStorage.Remotes.DataPatch", { settings = settings }, {})
	h:settle(3)
end

-- =============================================================================================
-- Contrôles
-- =============================================================================================

local function topRoot(h)
	local FocusGuard = h:require(CLIENT .. "UI.FocusGuard")
	local top = FocusGuard.top()
	return if top then top.root else nil
end

local function decorative(obj)
	local cur = obj
	while cur ~= nil and not cur:IsA("LayerCollector") do
		if cur:GetAttribute("Decorative") == true then
			return true
		end
		cur = cur.Parent
	end
	return false
end

local function onScreen(h, r)
	if r.clip ~= nil then
		local c = r.clip
		if r.x + r.w <= c.x + 1 or r.x >= c.x + c.w - 1 or r.y + r.h <= c.y + 1 or r.y >= c.y + c.h - 1 then
			return false
		end
	end
	return r.x + r.w > 0 and r.y + r.h > 0 and r.x < h.viewport.X and r.y < h.viewport.Y
end

local function isContent(obj)
	if not obj:IsA("GuiObject") then
		return false
	end
	local isText = obj.ClassName == "TextLabel" or obj.ClassName == "TextButton"
	if isText and obj.Text ~= "" and obj.TextTransparency < 1 then
		return true
	end
	return Layout.selectable(obj)
end

-- Textes et objets sélectionnables qui se recouvrent sous root
function TvAudit.overlaps(h, root)
	root = root or topRoot(h)
	if root == nil then
		return {}
	end
	Layout.apply(h)
	local items = {}
	local list = root:GetDescendants()
	table.insert(list, 1, root)
	for _, obj in list do
		if isContent(obj) and Layout.visible(obj) and not decorative(obj) then
			local r = Layout.rect(obj)
			if r and r.w > 1 and r.h > 1 and onScreen(h, r) then
				table.insert(items, { obj = obj, r = r })
			end
		end
	end
	local issues = {}
	for i = 1, #items do
		local a = items[i]
		for j = i + 1, #items do
			local b = items[j]
			if not a.obj:IsDescendantOf(b.obj) and not b.obj:IsDescendantOf(a.obj) then
				local ox = math.min(a.r.x + a.r.w, b.r.x + b.r.w) - math.max(a.r.x, b.r.x)
				local oy = math.min(a.r.y + a.r.h, b.r.y + b.r.h) - math.max(a.r.y, b.r.y)
				if ox > 2 and oy > 2 then
					table.insert(issues, `chevauchement : {Layout.name(a.obj)} × {Layout.name(b.obj)}`)
				end
			end
		end
	end
	table.sort(issues)
	return issues
end

local function auditFiltered(h, root, prefixes, safeArea)
	root = root or topRoot(h)
	if root == nil then
		return {}
	end
	local out = {}
	for _, issue in Gamepad.audit(h, { root = root, minText = 28, safeArea = safeArea }) do
		for _, p in prefixes do
			if string.sub(issue, 1, #p) == p then
				table.insert(out, issue)
				break
			end
		end
	end
	return out
end

-- Texte coupé ou trop petit (< 28 px TV)
function TvAudit.clipped(h, root)
	return auditFiltered(h, root, { "texte coupé", "texte trop petit" }, false)
end

-- Hors de la zone sûre TV (5 %) : objets sélectionnables et textes visibles, sur leur partie
-- réellement affichée (un cadre défilant ou ClipsDescendants coupe la demi-rangée qui dépasse)
function TvAudit.outsideSafe(h, root)
	root = root or topRoot(h)
	if root == nil then
		return {}
	end
	Layout.apply(h)
	local vx, vy = h.viewport.X, h.viewport.Y
	local x0, y0, x1, y1 = vx * 0.05, vy * 0.05, vx * 0.95, vy * 0.95
	local issues = {}
	local list = root:GetDescendants()
	table.insert(list, 1, root)
	for _, obj in list do
		if isContent(obj) and Layout.visible(obj) and not decorative(obj) then
			local r = Layout.rect(obj)
			if r and r.w > 1 and r.h > 1 and onScreen(h, r) then
				local ax, ay, bx, by = r.x, r.y, r.x + r.w, r.y + r.h
				if r.clip then
					ax = math.max(ax, r.clip.x)
					ay = math.max(ay, r.clip.y)
					bx = math.min(bx, r.clip.x + r.clip.w)
					by = math.min(by, r.clip.y + r.clip.h)
				end
				if ax < x0 - 0.5 or ay < y0 - 0.5 or bx > x1 + 0.5 or by > y1 + 0.5 then
					table.insert(
						issues,
						string.format(
							"hors de la zone sûre TV : %s (%d, %d, %d × %d)",
							Layout.name(obj),
							math.floor(ax),
							math.floor(ay),
							math.floor(bx - ax),
							math.floor(by - ay)
						)
					)
				end
			end
		end
	end
	table.sort(issues)
	return issues
end

-- Glyphes non PlayStation (console), lettres de bouton Xbox
function TvAudit.glyphs(h, root)
	return auditFiltered(h, root, { "glyphe non PlayStation", "texte de bouton Xbox" }, false)
end

-- Touches du jeu encore liées derrière une fenêtre
function TvAudit.boundBehindWindow(h)
	local FocusGuard = h:require(CLIENT .. "UI.FocusGuard")
	if not FocusGuard.anyOpen() then
		return {}
	end
	local issues = {}
	for name, b in h.actionBindings do
		if not TvAudit.UI_ACTIONS[name] then
			local menuOnly = true
			local game = false
			for _, k in b.keys do
				local keyName = if typeof(k) == "EnumItem" then k.Name else tostring(k)
				if not MENU_KEYS[keyName] then
					menuOnly = false
				end
				if GAME_KEYS[keyName] then
					game = true
				end
			end
			if game and not menuOnly then
				table.insert(issues, `touche du jeu liée derrière une fenêtre : {name}`)
			end
		end
	end
	table.sort(issues)
	return issues
end

-- Sélection : dans la fenêtre active (fenêtre ouverte), jamais posée en jeu
function TvAudit.selection(h)
	local FocusGuard = h:require(CLIENT .. "UI.FocusGuard")
	local selected = h.game.GuiService.SelectedObject
	local top = FocusGuard.top()
	if top == nil then
		if selected ~= nil then
			local gui = selected:FindFirstAncestorOfClass("ScreenGui")
			if gui == nil or gui.Name ~= "Loading" then
				return { "sélection posée en jeu : " .. Layout.name(selected) }
			end
		end
		return {}
	end
	if selected == nil then
		return { `sélection vide dans la fenêtre « {top.name} »` }
	end
	if selected ~= top.root and not selected:IsDescendantOf(top.root) then
		return { `sélection hors de la fenêtre « {top.name} » : {Layout.name(selected)}` }
	end
	Layout.apply(h)
	if not Layout.visible(selected) then
		return { `sélection invisible : {Layout.name(selected)}` }
	end
	return {}
end

-- Navigation à la croix, même règle que Layout.step (NextSelection* explicite, puis l'objet le plus
-- proche dans la direction, d'abord dans le SelectionGroup le plus proche, jamais au-delà d'un
-- comportement Stop), avec la liste des objets sélectionnables calculée UNE fois par écran (Layout.step
-- la recalcule à chaque pas : trop lent pour parcourir tous les écrans à 3 résolutions et 2 langues)
local DIRS = {
	Up = Vector2.new(0, -1),
	Down = Vector2.new(0, 1),
	Left = Vector2.new(-1, 0),
	Right = Vector2.new(1, 0),
}

local function center(r)
	return Vector2.new(r.x + r.w / 2, r.y + r.h / 2)
end

local function bestOf(candidates, from, dir)
	local origin = center(Layout.rect(from))
	local winner, score = nil, math.huge
	for _, c in candidates do
		if c ~= from then
			local v = center(Layout.rect(c)) - origin
			local along = v.X * dir.X + v.Y * dir.Y
			if along > 0.5 then
				local perp = math.abs(v.X * dir.Y - v.Y * dir.X)
				local sc = along + 2 * perp
				if sc < score then
					winner, score = c, sc
				end
			end
		end
	end
	return winner
end

function TvAudit.reachable(h, start, all)
	all = all or Layout.selectables(h)
	local groups = {}
	local function inside(group)
		local list = groups[group]
		if list == nil then
			list = {}
			for _, c in all do
				if c:IsDescendantOf(group) then
					table.insert(list, c)
				end
			end
			groups[group] = list
		end
		return list
	end
	local function step(from, dirName)
		local explicit = from["NextSelection" .. dirName]
		if explicit ~= nil and Layout.selectable(explicit) then
			return explicit
		end
		if Layout.rect(from) == nil then
			return nil
		end
		local vec = DIRS[dirName]
		local cur = from.Parent
		while cur ~= nil and (cur:IsA("GuiObject") or cur:IsA("LayerCollector")) do
			if cur.SelectionGroup == true then
				local found = bestOf(inside(cur), from, vec)
				if found then
					return found
				end
				if cur["SelectionBehavior" .. dirName] == Enum.SelectionBehavior.Stop then
					return nil
				end
			end
			cur = cur.Parent
		end
		return bestOf(all, from, vec)
	end
	local seen = { [start] = true }
	local queue = { start }
	local i = 1
	while queue[i] do
		local cur = queue[i]
		i += 1
		for dirName in DIRS do
			local nxt = step(cur, dirName)
			if nxt and not seen[nxt] then
				seen[nxt] = true
				table.insert(queue, nxt)
			end
		end
	end
	return seen
end

-- Objets atteints à la croix hors de la fenêtre active
function TvAudit.escapes(h, seen)
	local root = topRoot(h)
	local selected = h.game.GuiService.SelectedObject
	if root == nil or selected == nil then
		return {}
	end
	if seen == nil then
		Layout.apply(h)
		seen = TvAudit.reachable(h, selected)
	end
	local out = {}
	for obj in seen do
		if obj ~= root and not obj:IsDescendantOf(root) then
			table.insert(out, "la sélection s'échappe vers : " .. Layout.name(obj))
		end
	end
	table.sort(out)
	return out
end

-- Tous les contrôles de l'écran affiché (seen : objets atteints à la croix, déjà calculés)
function TvAudit.check(h, label, seen)
	local issues = {}
	local function add(list)
		for _, issue in list do
			table.insert(issues, (label or "") .. issue)
		end
	end
	add(TvAudit.selection(h))
	add(TvAudit.boundBehindWindow(h))
	local root = topRoot(h)
	if root then
		add(TvAudit.escapes(h, seen))
		add(TvAudit.overlaps(h, root))
		-- un seul audit de Gamepad (une mise en page) pour les textes et les glyphes
		for _, issue in Gamepad.audit(h, { root = root, minText = 28, safeArea = false }) do
			if
				string.sub(issue, 1, 11) == "texte coupé"
				or string.sub(issue, 1, 16) == "texte trop petit"
				or string.sub(issue, 1, 22) == "glyphe non PlayStation"
				or string.sub(issue, 1, 20) == "texte de bouton Xbox"
			then
				table.insert(issues, (label or "") .. issue)
			end
		end
		add(TvAudit.outsideSafe(h, root))
	end
	return issues
end

-- =============================================================================================
-- Parcours à 3 touches
-- =============================================================================================

-- Identité de l'écran affiché : fenêtre, onglet du panneau, sous-niveau (enfant du corps du panneau
-- qui contient la sélection : grille, fiche, aperçu…)
function TvAudit.screenId(h)
	local FocusGuard = h:require(CLIENT .. "UI.FocusGuard")
	local top = FocusGuard.top()
	if top == nil then
		return "game"
	end
	local id = top.name
	local panel = string.match(top.name, "^panel:(.+)$")
	if panel then
		local mod = h:require(CLIENT .. "UI.Panels." .. panel)
		local tab = if type(mod.currentTab) == "function" then mod.currentTab() else ""
		if tab ~= "" then
			id ..= "/" .. tab
		end
		local selected = h.game.GuiService.SelectedObject
		local body = top.root:FindFirstChild("Body")
		if selected and body and selected:IsDescendantOf(body) then
			local cur = selected
			while cur.Parent ~= body do
				cur = cur.Parent
			end
			id ..= "/" .. cur.Name
			-- page à deux niveaux (attribut TvLevels) : le sous-niveau qui contient la sélection
			if cur:GetAttribute("TvLevels") == true and selected ~= cur then
				local sub = selected
				while sub.Parent ~= cur do
					sub = sub.Parent
				end
				id ..= "/" .. sub.Name
			end
		end
	end
	return id
end

local function back(h)
	TvAudit.tick(h, 0.5)
	Gamepad.tap(h, Enum.KeyCode.ButtonB)
	TvAudit.tick(h, 0.5)
end

-- ○ jusqu'au jeu (12 appuis au plus) ; faux si une fenêtre reste ouverte
function TvAudit.toGame(h)
	local FocusGuard = h:require(CLIENT .. "UI.FocusGuard")
	for _ = 1, 12 do
		if not FocusGuard.anyOpen() then
			return true
		end
		back(h)
	end
	return not FocusGuard.anyOpen()
end

-- Ouvre le menu depuis le jeu : croix ↓ (InputController), sinon PanelController.toggleMenu
function TvAudit.openMenu(h)
	local FocusGuard = h:require(CLIENT .. "UI.FocusGuard")
	TvAudit.tick(h, 0.5)
	Gamepad.tap(h, Enum.KeyCode.DPadDown)
	if not FocusGuard.anyOpen() then
		h:require(CLIENT .. "UI.PanelController").toggleMenu()
		h:settle(2)
	end
	TvAudit.tick(h, 0.5)
	return FocusGuard.isOpen("menu")
end

local function activate(h, obj)
	TvAudit.tick(h, 0.5)
	h.game.GuiService.SelectedObject = obj
	h:settle(1)
	Gamepad.tap(h, Enum.KeyCode.ButtonA)
	TvAudit.tick(h, 0.5)
end

local function pathKey(obj)
	return Layout.name(obj)
end

-- Rejoue un chemin (liste d'objets) depuis le jeu ; faux si un pas n'est plus atteignable
local function replay(h, path)
	if not TvAudit.toGame(h) then
		return false
	end
	if not TvAudit.openMenu(h) then
		return false
	end
	for _, obj in path do
		if obj.Parent == nil or h.game.GuiService.SelectedObject == nil then
			return false
		end
		activate(h, obj)
	end
	return true
end

function TvAudit.walk(h, opts)
	opts = opts or {}
	local label = opts.label or ""
	local maxScreens = opts.maxScreens or 80
	local issues = {}
	local screens = {}
	local edges = {}
	local function add(list, prefix)
		for _, issue in list do
			table.insert(issues, label .. (prefix or "") .. issue)
		end
	end
	local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
	if not Clock.isFrozen() then
		Clock.freeze(1800000000)
	end
	if not TvAudit.toGame(h) then
		add({ "○ ne rend pas la main au jeu au départ" })
	end
	add(TvAudit.selection(h), "[game] ")
	if not TvAudit.openMenu(h) then
		add({ "le menu ne s'ouvre pas" })
		return { screens = screens, issues = issues, edges = edges }
	end
	local queue = { { id = TvAudit.screenId(h), path = {} } }
	screens[queue[1].id] = true
	Layout.apply(h)
	local firstSel = h.game.GuiService.SelectedObject
	add(TvAudit.check(h, `[{queue[1].id}] `, if firstSel then TvAudit.reachable(h, firstSel) else nil))
	local tried = {}
	local count = 1
	local qi = 1
	while queue[qi] and count < maxScreens do
		local node = queue[qi]
		qi += 1
		if replay(h, node.path) and TvAudit.screenId(h) == node.id then
			local selected = h.game.GuiService.SelectedObject
			Layout.apply(h)
			local targets = {}
			if selected then
				for obj in TvAudit.reachable(h, selected) do
					if obj:GetAttribute("TvNav") == true or obj:GetAttribute("TvTab") == true then
						table.insert(targets, obj)
					end
				end
			end
			table.sort(targets, function(a, b)
				return pathKey(a) < pathKey(b)
			end)
			for _, obj in targets do
				local key = node.id .. "|" .. pathKey(obj)
				if not tried[key] and count < maxScreens then
					tried[key] = true
					if replay(h, node.path) and TvAudit.screenId(h) == node.id then
						local isTab = obj:GetAttribute("TvTab") == true
						-- écran de l'objet activé : ○ doit y ramener
						h.game.GuiService.SelectedObject = obj
						h:settle(1)
						local before = TvAudit.screenId(h)
						local FocusGuard = h:require(CLIENT .. "UI.FocusGuard")
						local srcTop = FocusGuard.top()
						local srcWindow = if srcTop then srcTop.name else ""
						activate(h, obj)
						-- un panneau en a REMPLACÉ un autre (ex. « Dépenser d'abord » : Aperçu → Ranch) : son ○
						-- remonte au menu, comme tout panneau ouvert depuis le rail
						if
							srcWindow ~= ""
							and not FocusGuard.isOpen(srcWindow)
							and FocusGuard.isOpen("menu")
						then
							before = "menu"
						end
						local id = TvAudit.screenId(h)
						-- ✕ sans effet (refus : rien à ranger, enclos pleins…) : pas un nouvel écran
						local moved = isTab or h.game.GuiService.SelectedObject ~= obj
						if moved and id ~= node.id and not screens[id] and id ~= "game" then
							screens[id] = true
							count += 1
							table.insert(edges, { from = node.id, to = id, via = pathKey(obj) })
							Layout.apply(h)
							local newSel = h.game.GuiService.SelectedObject
							add(
								TvAudit.check(
									h,
									`[{id}] `,
									if newSel then TvAudit.reachable(h, newSel) else nil
								)
							)
							local path = table.clone(node.path)
							table.insert(path, obj)
							table.insert(queue, { id = id, path = path })
							-- ○ revient à l'écran d'origine, au besoin en remontant d'abord les sous-niveaux de
							-- l'écran atteint (3 appuis au plus) ; un onglet remonte au menu, comme son panneau
							if not isTab then
								local after = id
								for _ = 1, 3 do
									back(h)
									after = TvAudit.screenId(h)
									if after == before or after == "game" then
										break
									end
								end
								if after ~= before then
									add({
										`○ depuis {id} mène à {after} au lieu de {before} (écran {node.id}, objet {pathKey(
											obj
										)})`,
									})
								end
							end
							if not TvAudit.toGame(h) then
								add({ `○ répété ne rend pas la main au jeu depuis {id}` })
							end
						end
					end
				end
			end
		end
	end
	if not TvAudit.toGame(h) then
		add({ "○ ne rend pas la main au jeu à la fin" })
	end
	return { screens = screens, issues = issues, edges = edges }
end

-- Parcours à chaque résolution et dans chaque langue
function TvAudit.run(h, opts)
	opts = opts or {}
	local resolutions = opts.resolutions
		or { Vector2.new(1920, 1080), Vector2.new(3840, 2160), Vector2.new(1280, 720) }
	local langs = opts.langs or { "en", "fr" }
	local issues = {}
	local screens = {}
	for _, res in resolutions do
		local size = if typeof(res) == "Vector2" then res else Vector2.new(res.X, res.Y)
		TvAudit.setResolution(h, size)
		for _, lang in langs do
			TvAudit.setLanguage(h, lang)
			local label = `[{size.X}x{size.Y} {lang}] `
			local report = TvAudit.walk(h, { label = label, maxScreens = opts.maxScreens })
			for _, issue in report.issues do
				table.insert(issues, issue)
			end
			for id in report.screens do
				screens[id] = true
			end
		end
	end
	return { issues = issues, screens = screens }
end

-- Nombre d'objets d'interface (GuiObject) sous PlayerGui (budget ClientReplay : ≤ 3 000)
function TvAudit.guiObjects(h)
	local n = 0
	for _, d in h.localPlayer.PlayerGui:GetDescendants() do
		if d:IsA("GuiObject") then
			n += 1
		end
	end
	return n
end

return TvAudit
