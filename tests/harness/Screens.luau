--!nocheck
-- Scénarios d'écrans de Raise a Squishy (outil d'écrans repris de Comet Conga) : démarre le VRAI
-- client (Main.client) dans le harnais, sur un appareil et dans une langue donnés, lui envoie des
-- charges serveur réalistes (DataSnapshot, Celebrate, Banner, Feedback, ModePrompt,
-- LeaderboardState, DiagnosticsSnapshot…) et amène l'interface dans chaque état à vérifier.
-- Partagé par l'outil de captures (tools/screens/capture.luau) et les specs
-- tests/specs/TextFit_all.spec.luau et TextFit_keys.spec.luau.
--
--   local Screens = require("./Screens")
--   for _, group in Screens.groups() do
--       local c = Screens.boot(Harness, profile, "fr", group.state)
--       for _, screen in Screens.expand(c, group) do
--           Screens.show(c, screen)            -- amène l'interface dans l'état
--           Screens.layout(c)                  -- mise en page fidèle (textes mesurés)
--           ... Screens.textIssues(c) / ScreenDump.dump(c, …)
--       end
--   end
--
-- Appareils (PROFILES, console d'abord, aucun téléphone ni tablette) : téléviseur PS5 1920 × 1080,
-- 3840 × 2160 et 1280 × 720 (manette, glyphes PlayStation), PC 1366 × 768 (clavier-souris).
-- États : nouveau joueur (accueil pas à pas), milieu de partie, fin de partie (R XII, tout possédé),
-- très grands nombres (1e6 à 999 Dc, le dernier suffixe, puis 1,23e36), noms de joueurs de 20
-- caractères, noms d'espèces les plus longs, toutes les bannières, cartes, invites et textes du
-- monde. Chaque texte affiché par Prefs.t / Widgets.setText est relié à sa clé de localisation
-- (Screens.keyOf) : TextFit_keys vérifie chaque clé, dans les DEUX langues, dans chaque boîte où le
-- jeu l'affiche.

local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Layout = require("./Layout")
local TextFit = require("./TextFit")
local EngineProps = require("./EngineProps")
local TvAudit = require("./TvAudit")
local Gamepad = require("./Gamepad")
local MockInstance = require("./MockInstance")

local Enum = roblox.Enum
local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3

local Screens = {}

-- Suivi des propriétés écrites (valeurs par défaut du vrai moteur pour les autres) : posé par
-- Screens.boot / Screens.bootLoading avant le harnais ; Screens.finish() le retire (fin d'une spec)
function Screens.finish()
	EngineProps.uninstall()
end

local CLIENT = TvAudit.CLIENT
local REMOTES = "ReplicatedStorage.Remotes."
local T0 = 1800000000
Screens.T0 = T0
Screens.CLIENT = CLIENT
Screens.REMOTES = REMOTES

-- Noms de joueurs de 20 caractères (DisplayName Roblox : 20 au plus)
Screens.LONG_NAME = "MaximilianWolfgang20"
Screens.LONG_NAME_2 = "WilhelminaMcKenzie99"

Screens.PROFILES = {
	{ id = "tv1080", label = "PS5 TV 1920×1080 (manette)", w = 1920, h = 1080, console = true },
	{ id = "tv2160", label = "PS5 TV 3840×2160 (manette)", w = 3840, h = 2160, console = true },
	{ id = "tv720", label = "TV 1280×720 (manette)", w = 1280, h = 720, console = true },
	{ id = "pc", label = "PC 1366×768 (clavier-souris)", w = 1366, h = 768 },
}
Screens.LANGS = { "fr", "en" }

function Screens.profileById(id: string)
	for _, p in Screens.PROFILES do
		if p.id == id then
			return p
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------------------------
-- Profils de données
-- ---------------------------------------------------------------------------------------------

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

local ONBOARDING_DONE = { step = 11, done = true, demoDone = true }

-- kind : "new" | "mid" | "late" | "huge"
function Screens.profile(kind: string)
	if kind == "new" then
		return {}
	end
	local p = TvAudit.richProfile(T0)
	p.onboarding = deepCopy(ONBOARDING_DONE)
	if kind == "mid" then
		p.coins = 1234567
		p.pot = 98765
		p.fame = 12345
		-- dalle Enclos à son dernier niveau (14 : 4 + 14 = 18 places) et les squishies en trop dans la
		-- Boîte à dodo : sans cela l'outil montrait « 20 / 4 », un état que le serveur ne produit
		-- jamais (revue de l'outil)
		p.tiles = { snack = 0, decor = 0, pens = 14, cozyBed = false, seen = 0 }
		local inPens = {}
		for uid, sq in p.squishies do
			if sq.at == "pen" then
				table.insert(inPens, uid)
			end
		end
		table.sort(inPens, function(a, b)
			return (tonumber(string.sub(a, 2)) or 0) < (tonumber(string.sub(b, 2)) or 0)
		end)
		local extra = #inPens - 18
		for i = #inPens, 1, -1 do
			if extra > 0 and inPens[i] ~= "u20" then -- u20 : le plus gros (Grand Splorch prêt)
				p.squishies[inPens[i]].at = "dodo"
				extra -= 1
			end
		end
		-- Grand Splorch prêt (aperçu, puce d'action du HUD)
		p.squishies.u20.z = 300000
		return p
	end
	-- fin de partie : Grand Splorch XII, gros squishies, tout possédé
	p.R = 12
	p.coins = if kind == "huge" then 9.99e35 else 9.87654321e17
	p.pot = if kind == "huge" then 9.99e35 else 1.23456789e15
	p.fame = if kind == "huge" then 9.99e35 else 9.87654321e12
	p.plopDays = 999
	p.biggestEver = if kind == "huge" then 9.99e35 else 9.87e17
	for uid, sq in p.squishies do
		sq.z = (if kind == "huge" then 9.99e35 else 9.87e17) / (1 + (tonumber(string.sub(uid, 2)) or 1))
		sq.st = 5
	end
	p.passes = { AutoPot = true, DoubleCoins = true, BigRanch = true, SaddlesTrails = true }
	-- records de taille : un trophée de chaque palier de l'Étagère (bronze … cristal) dans le Squishydex
	local trophies = {}
	for i = 1, 26 do
		trophies[i] = 10 ^ (3 + 3 * ((i - 1) % 4)) * 1.5
	end
	p.trophies = trophies
	-- toutes les dalles au maximum (« Au maximum » dans Ranch › Dalles)
	p.tiles = { snack = 999, decor = 999, pens = 999, cozyBed = true, seen = 15 }
	p.outfits = { owned = { plopBib = 3, sweater = 3, crown = 2, winter = 2 }, worn = {} }
	return p
end

-- ---------------------------------------------------------------------------------------------
-- Démarrage
-- ---------------------------------------------------------------------------------------------

local function frames(c, n, dt)
	for _ = 1, n or 3 do
		c.Clock.advance(dt or 1 / 30)
		c.h:step(dt or 1 / 30, 1)
	end
	c.h:settle(1)
end
Screens.frames = frames

-- Relie les textes produits par la localisation à leur clé : Localization.get enveloppé (même
-- résultat), dernier couple (texte → clé, variables) retenu
local function hookLocalization(c)
	local L = c.h:require("ReplicatedStorage.Shared.Localization")
	local get = L.get
	c.keyOfText = {}
	-- un même texte peut venir de plusieurs clés (« Grand Splorch » : menu.splorch, hud.splorch…) :
	-- toutes sont mesurées dans la boîte ; les textes mis en capitales par le jeu (string.upper)
	-- sont reliés aussi
	local function note(text, key, vars)
		local set = c.keyOfText[text]
		if set == nil then
			set = {}
			c.keyOfText[text] = set
		end
		set[key] = vars or false
	end
	L.get = function(lang, key, vars)
		local out = get(lang, key, vars)
		if type(out) == "string" and out ~= "" and type(key) == "string" then
			local copy = if type(vars) == "table" then table.clone(vars) else nil
			note(out, key, copy)
			local upper = string.upper(out)
			if upper ~= out then
				note(upper, key, copy)
			end
		end
		return out
	end
end

-- Client complet démarré pour `profile` (entrée de PROFILES), `lang` ("fr" | "en") et l'état de
-- données `state` ("new" | "mid" | "late" | "huge")
function Screens.boot(Harness, profile, lang: string, state: string)
	EngineProps.install()
	local c = { profile = profile, lang = lang, state = state, players = {} }
	local data = Screens.profile(state)
	local h = TvAudit.client({
		console = profile.console == true,
		viewport = Vector2.new(profile.w, profile.h),
		lang = lang,
		now = T0,
		profile = data,
		before = function(hh)
			c.h = hh
			hh.localPlayer.LocaleId = if lang == "fr" then "fr-fr" else "en-us"
			hh.localPlayer.DisplayName = Screens.LONG_NAME
			TvAudit.enableShop(hh)
			hookLocalization(c)
			Screens.realTextService()
		end,
	})
	c.h = h
	c.data = data
	c.Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
	c.PC = h:require(CLIENT .. "UI.PanelController")
	c.HUD = h:require(CLIENT .. "UI.HUD")
	c.Cards = h:require(CLIENT .. "UI.Cards")
	c.Banners = h:require(CLIENT .. "UI.Banners")
	c.Toast = h:require(CLIENT .. "UI.Toast")
	c.Messages = h:require(CLIENT .. "UI.Hud.Messages")
	c.Root = h:require(CLIENT .. "UI.Root")
	c.FocusGuard = h:require(CLIENT .. "UI.FocusGuard")
	c.ReturnScreen = h:require(CLIENT .. "UI.ReturnScreen")
	c.Prefs = h:require(CLIENT .. "Util.Prefs")
	c.WSC = h:require(CLIENT .. "Controllers.WorldStateController")
	c.Prompt = h:require(CLIENT .. "Controllers.PromptController")
	c.Chase = h:require(CLIENT .. "Controllers.ChaseController")
	c.Strings = h:require("ReplicatedStorage.Shared.Localization.Strings")
	c.Localization = h:require("ReplicatedStorage.Shared.Localization")
	c.BigNumber = h:require("ReplicatedStorage.Shared.Logic.BigNumber")
	c.Species = h:require("ReplicatedStorage.Shared.Config.Species")
	c.Mutations = h:require("ReplicatedStorage.Shared.Config.Mutations")
	c.EventClock = h:require("ReplicatedStorage.Shared.Logic.EventClock")
	c.stubs = {}
	-- joueurs du serveur aux noms longs (bannières, classements, cartes « booped »)
	for i, name in { Screens.LONG_NAME_2, "Léa", "Noah", "ÉlodieBérénice2026" } do
		local p = h:addPlayer({ userId = i + 1, name = name })
		p.DisplayName = name
		table.insert(c.players, p)
	end
	-- le joueur dans son ranch (slot 1), immobile
	c.WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
	Screens.ranchStub(c, "cozy")
	h:moveTo(h.localPlayer, c.WorldLayout.spawnCFrame(1).Position + Vector3.new(0, 3, 0))
	frames(c, 10)
	return c
end

-- TextService:GetTextSize du harnais remplacé par la vraie mesure (TextFit, largeurs des polices) :
-- le jeu qui mesure ses textes (Widgets.longestWord) voit les mêmes largeurs que l'outil
function Screens.realTextService()
	local cm = MockInstance.classMethods.TextService
	if cm == nil then
		return
	end
	cm.GetTextSize = function(_, text, size, font, frame)
		local okFace, face = pcall(roblox.Font.fromEnum, font)
		local key = TextFit.fontKey(if okFace then face else nil)
		local maxW = if typeof(frame) == "Vector2" and frame.X < 1e4 then frame.X else nil
		local lines, _, widths = TextFit.lines(tostring(text), key, size, maxW)
		local w = 0
		for _, lw in widths do
			w = math.max(w, lw)
		end
		return Vector2.new(math.ceil(w), #lines * size)
	end
end

-- Remplace une fonction d'un module du client (restaurée par Screens.unstub)
local function stub(c, mod, name, fn)
	table.insert(c.stubs, { mod = mod, name = name, fn = mod[name] })
	mod[name] = fn
end

local function unstub(c)
	for i = #c.stubs, 1, -1 do
		local s = c.stubs[i]
		s.mod[s.name] = s.fn
	end
	table.clear(c.stubs)
end
Screens.unstub = unstub

-- Nom d'espèce le plus long de la langue (id), nom de mutation le plus long (id)
local function longestSpecies(c)
	if c.longestSpeciesId and c.longestSpeciesLang == c.lang then
		return c.longestSpeciesId
	end
	local best, bestLen = 1, -1
	for _, def in c.Species.List do
		local name = c.Prefs.t("species." .. def.key)
		if utf8.len(name) and utf8.len(name) > bestLen then
			best, bestLen = def.id, utf8.len(name)
		end
	end
	c.longestSpeciesId, c.longestSpeciesLang = best, c.lang
	return best
end
Screens.longestSpecies = longestSpecies

local function longestMutation(c)
	local best, bestLen = 1, -1
	for id, def in c.Mutations.ById do
		local name = c.Prefs.t("mutation." .. def.key)
		if utf8.len(name) and utf8.len(name) > bestLen then
			best, bestLen = id, utf8.len(name)
		end
	end
	return best
end

-- ---------------------------------------------------------------------------------------------
-- Aides d'état
-- ---------------------------------------------------------------------------------------------

-- Toasts / messages encore affichés masqués (chaque écran ne montre que les siens)
local function hideToasts(c)
	local gui = c.h.localPlayer.PlayerGui
	for _, name in { "Toasts", "Toast" } do
		local t = gui:FindFirstChild(name)
		if t then
			for _, d in t:GetDescendants() do
				if d:IsA("GuiObject") and d.Name == "Toast" then
					d.Visible = false
				end
			end
		end
	end
end
Screens.hideToasts = hideToasts

local function closeAll(c)
	hideToasts(c)
	pcall(c.PC.closeAll)
	-- fenêtres restées ouvertes (carte du choix, carte rouverte) : ○, comme le joueur
	for _ = 1, 3 do
		if not c.FocusGuard.anyOpen() then
			break
		end
		c.Clock.advance(1)
		Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
		c.h:settle(2)
	end
	if c.ReturnScreen.isOpen() then
		pcall(c.ReturnScreen._close)
	end
	frames(c, 6, 0.5)
	c.h.game.GuiService.SelectedObject = nil
end
Screens.closeAll = closeAll

-- Bannière en cours et file terminées ; messages de la file passés
local function flushBanners(c)
	for _ = 1, 16 do
		if c.Banners.current() == nil and c.Banners.queued() == 0 then
			break
		end
		frames(c, 3, 2)
	end
end

local function flushMessages(c)
	for _ = 1, 30 do
		if c.Messages.pending() == 0 and not c.Messages.busy(c.Clock.now()) then
			break
		end
		frames(c, 2, 2)
	end
	hideToasts(c)
end

local function flushCards(c)
	for _ = 1, 20 do
		if c.Cards.current() == nil and c.Cards.queued() == 0 then
			break
		end
		frames(c, 3, 4)
	end
end

local function flushAll(c)
	flushBanners(c)
	flushMessages(c)
	flushCards(c)
end
Screens.flushAll = flushAll

-- Panneau ouvert depuis le jeu (fermé avant), comme au rail
local function open(c, name, tab)
	closeAll(c)
	c.PC.open(name, tab)
	frames(c, 10, 0.1)
end
Screens.open = open

-- ✕ sur un objet (sélection posée puis croix), comme TvAudit
local function activate(c, obj)
	c.h.game.GuiService.SelectedObject = obj
	c.h:settle(1)
	frames(c, 2, 0.5)
	Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
	frames(c, 6, 0.2)
end
Screens.activate = activate

-- Instant de l'horloge du jeu (≥ T0) où `pred(t)` est vrai, par pas de 30 s (≤ 9 jours)
local function findTime(pred, from)
	local start = from or T0
	for i = 0, 9 * 2880 do
		local t = start + 30 * i
		local ok, yes = pcall(pred, t)
		if ok and yes then
			return t
		end
	end
	return nil
end

-- Instant calme (aucun événement, prochain Rush à plus de 3 min, pas de sirène) à partir de maintenant :
-- l'horloge du jeu ne recule jamais
local function calm(c)
	local now = c.Clock.now()
	local E = c.EventClock
	local t = findTime(function(t)
		local r = E.rush(t)
		if
			r.active
			or (r.sirenAt > t and r.sirenAt - t < 180)
			or (r.startsAt > t and r.startsAt - t < 180)
		then
			return false
		end
		local m = E.mega(t)
		if m.active or (m.warnAt > t and m.warnAt - t < 180) then
			return false
		end
		return not E.moon(t).active and not E.golden(t).active
	end, math.ceil(now))
	if t and t > now then
		c.Clock.freeze(t)
	end
	frames(c, 2, 0.1)
end
Screens.calm = calm

-- Événement du serveur simulé : features ouvertes, sans attendre EventState
local FEATURES = {
	boopRush = "on",
	megaSquish = true,
	golden = true,
	jellyMoon = true,
	gauge = true,
	clips = true,
	costume = "",
	diagnostics = true,
}

local function eventStub(c, now, over)
	local ev = {
		features = table.clone(FEATURES),
		boost = { kind = "", untilT = 0, byName = "" },
		gauge = { points = 400, target = 1200, partyUntil = 0, restUntil = 0 },
		spectacle = { queue = {} },
		mega = { phase = "idle", points = 0, target = 0 },
		golden = { active = false, id = 0, endsAt = 0 },
		moon = { active = false, session = 0, endsAt = 0, nextAt = 0 },
		rush = { active = false, index = 0, endsAt = 0, nextAt = 0, moonBoopable = false },
	}
	for k, v in over or {} do
		ev[k] = v
	end
	stub(c, c.WSC, "event", function()
		return ev
	end)
	return ev
end

-- Ranchs du serveur (RanchSnapshot réel, numéro de suite croissant) : le mien (slot 1, nom de 20
-- caractères, titre le plus long), un voisin au nom long, un ranch au nom caché (alias), un libre
local function ranchPublic(c, slot, userId, name, over)
	local r = {
		slot = slot,
		userId = userId,
		name = name,
		hidden = false,
		R = if c.state == "late" or c.state == "huge" then 12 else 3,
		fame = if c.state == "huge" then 9.99e35 else 123456,
		day = 999,
		mode = "cozy",
		shield = false,
		boopable = false,
		tiles = { snack = 5, decor = 5, pens = 3, cozyBed = true, seen = 0 },
		vat = true,
		pool = true,
		vatFill = 0,
		growth = { G = 0, g = 1, t = T0 },
		carry = "",
		ride = "",
		saddle = 2,
		waiting = "",
		theme = "",
		flag = "",
		title = "plops_best_friend",
		saddleColor = "",
		trail = "",
		best = { s = longestSpecies(c), m = 0, z = 9.87e17, zg = 0 },
	}
	if c.state == "new" then
		-- nouveau joueur : rien de construit, ni Fame ni dalles
		r.R, r.fame, r.day, r.vat, r.pool, r.saddle, r.title = 0, 0, 1, false, false, 0, ""
		r.tiles = { snack = 0, decor = 0, pens = 0, cozyBed = false, seen = 0 }
		r.best = { s = 0, m = 0, z = 0, zg = 0 }
	end
	for k, v in over or {} do
		r[k] = v
	end
	return r
end

local function ranchStub(c, mode, extra)
	c.seq = (c.seq or 0) + 1
	local mine = ranchPublic(c, 1, c.h.localPlayer.UserId, Screens.LONG_NAME, { mode = mode or "cozy" })
	for k, v in extra or {} do
		mine[k] = v
	end
	local ranches = {
		["1"] = mine,
		["2"] = ranchPublic(
			c,
			2,
			c.players[1].UserId,
			Screens.LONG_NAME_2,
			{ mode = "rush", boopable = true }
		),
		["3"] = ranchPublic(c, 3, c.players[4].UserId, "", { hidden = true, title = "" }),
		["4"] = ranchPublic(c, 4, 0, "", { title = "", best = { s = 0, m = 0, z = 0, zg = 0 }, R = 0 }),
	}
	local squishies = {}
	for slot = 1, 3 do
		local list = {}
		for i = 1, 6 do
			local first = slot == 1 and i == 1
			list["p" .. slot .. i] = {
				s = if first then longestSpecies(c) else ((i * 5 + slot) % 26) + 1,
				m = if first then longestMutation(c) else i % 3,
				st = i % 6,
				z = if first then (if c.state == "huge" then 9.99e35 else 9.87e17) else 9.87e5 * i,
				zg = 0,
				at = "pen",
				bf = 0,
				o = "",
				ready = 0,
			}
		end
		squishies[tostring(slot)] = list
	end
	c.h:fireClient(REMOTES .. "RanchSnapshot", { seq = c.seq, ranches = ranches, squishies = squishies })
	c.h:settle(2)
end
Screens.ranchStub = ranchStub

local function refreshHud(c)
	pcall(c.HUD._refresh)
	pcall(c.h:require(CLIENT .. "UI.Prompt")._step)
	frames(c, 3, 1 / 30)
end

-- ---------------------------------------------------------------------------------------------
-- Écrans
-- ---------------------------------------------------------------------------------------------

local EVENT_SCREENS = { ["hud.rush"] = true, ["hud.mega"] = true, ["hud.moon"] = true, ["hud.golden"] = true }

local function hudScreen(id, setup)
	return {
		id = id,
		event = EVENT_SCREENS[id] == true,
		run = function(c)
			closeAll(c)
			flushAll(c)
			unstub(c)
			if setup then
				setup(c)
			end
			refreshHud(c)
		end,
	}
end

-- HUD dans chaque mode : Rush, Cozy, MEGA (pression), Jelly Moon, Golden, fête, sieste de Big Plop,
-- Grand Splorch en file, APPLAUDIR, cible, invite, bond en recharge
local function hudModes()
	local list = {}
	table.insert(
		list,
		hudScreen("hud.cozy", function(c)
			ranchStub(c, "cozy")
			eventStub(c, c.Clock.now())
		end)
	)
	table.insert(
		list,
		hudScreen("hud.rush", function(c)
			local t = findTime(function(t)
				return c.EventClock.rush(t).active
			end, math.ceil(c.Clock.now()))
			if t then
				c.Clock.freeze(t + 5)
			end
			ranchStub(c, "rush", { shield = true })
			eventStub(c, c.Clock.now())
		end)
	)
	table.insert(
		list,
		hudScreen("hud.mega", function(c)
			local t = findTime(function(t)
				local m = c.EventClock.mega(t)
				return m.active and t < m.endsAt
			end, math.ceil(c.Clock.now()))
			if t then
				c.Clock.freeze(t + 2)
			end
			ranchStub(c, "cozy")
			eventStub(c, c.Clock.now(), {
				mega = { phase = "press", points = 987654321, target = 1.23456789e9, index = 1 },
			})
		end)
	)
	table.insert(
		list,
		hudScreen("hud.moon", function(c)
			local t = findTime(function(t)
				return c.EventClock.moon(t).active
			end, math.ceil(c.Clock.now()))
			if t then
				c.Clock.freeze(t + 5)
			end
			ranchStub(c, "cozy")
			eventStub(c, c.Clock.now())
		end)
	)
	table.insert(
		list,
		hudScreen("hud.golden", function(c)
			local t = findTime(function(t)
				return c.EventClock.golden(t).active
			end, math.ceil(c.Clock.now()))
			if t then
				c.Clock.freeze(t + 5)
			end
			ranchStub(c, "rush")
			eventStub(c, c.Clock.now(), { golden = { active = true, id = 1, endsAt = c.Clock.now() + 299 } })
			stub(c, c.Chase, "cooldownLeft", function()
				return 2
			end)
		end)
	)
	table.insert(
		list,
		hudScreen("hud.party", function(c)
			ranchStub(c, "cozy")
			eventStub(c, c.Clock.now(), {
				boost = { kind = "squish", untilT = c.Clock.now() + 3599, byName = Screens.LONG_NAME_2 },
			})
		end)
	)
	table.insert(
		list,
		hudScreen("hud.rest", function(c)
			ranchStub(c, "cozy")
			eventStub(c, c.Clock.now(), {
				gauge = { points = 1199, target = 1200, partyUntil = 0, restUntil = c.Clock.now() + 754 },
			})
		end)
	)
	table.insert(
		list,
		hudScreen("hud.full", function(c)
			-- tout ensemble (comme Layout_hud) : bouclier, ×2, file, APPLAUDIR, cible, bond, message
			ranchStub(c, "rush", { shield = true })
			local now = c.Clock.now()
			eventStub(c, now, {
				boost = { kind = "wobble", untilT = now + 299, byName = "" },
				gauge = { points = 400, target = 1200, partyUntil = 0, restUntil = now + 754 },
				spectacle = {
					queue = {
						{
							kind = "splorch",
							userId = 1,
							startAt = now + 40,
							slot = 1,
							position = 2,
							eta = 40,
						},
					},
				},
			})
			stub(c, c.Prompt, "current", function()
				return {
					kind = "squishy",
					slot = 1,
					uid = "p11",
					primary = "press",
					secondary = "pickup",
					ready = true,
					position = Vector3.new(0, 2, -6),
				}
			end)
			stub(c, c.Chase, "cooldownLeft", function()
				return 2
			end)
			c.h:fireClient(REMOTES .. "ClapPrompt", { heroId = c.players[1].UserId, endsAt = now + 8 })
			c.h:fireClient(
				REMOTES .. "Feedback",
				{ key = "feedback.notEnoughCoins", vars = { missing = 1.23456789e18 }, tone = "warning" }
			)
			c.h:settle(2)
		end)
	)
	-- invites du monde : chaque verbe principal, avec et sans la 2e ligne
	for _, primary in
		{ "press", "throw", "fusion", "putInPool", "buy", "boop", "feed", "catch", "sell", "shop", "petsit" }
	do
		table.insert(
			list,
			hudScreen("prompt." .. primary, function(c)
				ranchStub(c, "cozy")
				eventStub(c, c.Clock.now())
				stub(c, c.Prompt, "current", function()
					return {
						kind = "squishy",
						slot = 1,
						uid = "p11",
						primary = primary,
						secondary = if primary == "press" then "pickup" else "putdown",
						ready = true,
						position = Vector3.new(0, 2, -6),
					}
				end)
			end)
		)
	end
	return list
end

-- Panneaux et onglets
local PANEL_TABS = {
	{ "Ranch", { "pens", "dodo", "mail", "fuse", "sell", "pads", "style" } },
	{ "Squishydex", { "species", "families", "guide" } },
	{ "Objectives", { "today", "plop", "onboarding" } },
	{ "Leaderboards", { "stamps", "combo", "catchScore", "helpful", "generous" } },
	{ "Shop", { "passes", "party", "outfits" } },
	{ "Settings", { "" } },
	{ "SplorchPreview", { "" } },
	-- identifiants de Config/Cosmetics (« crown » n'existait pas : l'Aperçu restait sur le Pull)
	{ "OutfitPreview", { "sweater", "jellyCrown", "winterScarf", "plopBib" } },
	-- « probe » : panneau TextProbe (lot B1), photographié sur la PS5
	{ "Diagnostics", { "server", "client", "today", "tools", "probe" } },
}
Screens.PANEL_TABS = PANEL_TABS

local function leaderboards(c, huge)
	local boards = {}
	for i, cat in { "stamps", "combo", "catchScore", "helpful", "generous" } do
		local top, server = {}, {}
		for r = 1, 10 do
			local name = if r % 3 == 1
				then Screens.LONG_NAME_2
				elseif r % 3 == 2 then ""
				else "ÉlodieBérénice2026"
			table.insert(top, {
				rank = r,
				userId = 1000 + r,
				name = name,
				value = (if huge then 9.99e35 else 9.87654321e12) / r,
			})
		end
		for r = 1, 5 do
			table.insert(server, {
				rank = r,
				userId = if r == 2 then 1 else 2000 + r,
				name = if r == 2 then Screens.LONG_NAME else Screens.LONG_NAME_2,
				value = 98765 * (6 - r) * i,
			})
		end
		boards[cat] = {
			top = top,
			server = server,
			mine = if huge then 9.99e35 else 987654321,
			minePrev = 98765432,
			myServerRank = 2,
		}
	end
	c.h:fireClient(REMOTES .. "LeaderboardState", { week = 3, boards = boards })
	frames(c, 3)
end

local function diagnostics(c)
	local now = c.Clock.now()
	local entries = {}
	for i = 1, 6 do
		table.insert(entries, {
			key = "k" .. i,
			kind = if i % 2 == 0 then 2 else 1,
			text = "ServerScriptService.Server.Services.RanchService:# attempt to index nil with 'Position' <joueur> #",
			source = if i % 3 == 0 then "client" else "server",
			count = 98765,
			players = 16,
			first = now - 3600,
			last = now,
		})
	end
	local samples = {
		{
			key = "k1",
			text = entries[1].text,
			trace = "RanchService:412\nEconomyService:88",
			ctx = "slot=1",
			at = now,
		},
	}
	c.h:fireClient(REMOTES .. "DiagnosticsSnapshot", { tab = 0 })
	frames(c, 2)
	for tab = 1, 3 do
		c.h:fireClient(REMOTES .. "DiagnosticsSnapshot", {
			tab = tab,
			server = {
				placeVersion = 9876,
				utc = now,
				uptime = 359999,
				players = 16,
				tickAvgMs = 12.34,
				tickMaxMs = 123.4,
				memoryMb = 1234.5,
				timedOut = 98,
			},
			entries = entries,
			samples = samples,
			today = entries,
		})
	end
	frames(c, 2)
end

local function panelScreens(state)
	local list = {}
	table.insert(list, {
		id = "menu",
		run = function(c)
			closeAll(c)
			c.PC.openMenu()
			frames(c, 8, 0.1)
		end,
	})
	for _, entry in PANEL_TABS do
		local panel, tabs = entry[1], entry[2]
		for _, tab in tabs do
			local id = "panel." .. panel .. (if tab ~= "" then "." .. tab else "")
			table.insert(list, {
				id = id,
				run = function(c)
					unstub(c)
					if panel == "Leaderboards" then
						leaderboards(c, state == "huge")
					elseif panel == "Diagnostics" then
						diagnostics(c)
					end
					open(c, panel, if tab ~= "" then tab else nil)
				end,
			})
			-- 2e niveau : ✕ sur la sélection par défaut (fiche d'un squishy, d'une espèce…)
			if
				(panel == "Ranch" and (tab == "pens" or tab == "fuse" or tab == "sell"))
				or (panel == "Squishydex" and tab == "species")
				or (panel == "Diagnostics" and tab == "server")
			then
				table.insert(list, {
					id = id .. ".open",
					run = function(c)
						unstub(c)
						if panel == "Diagnostics" then
							diagnostics(c)
						end
						open(c, panel, tab)
						local sel = c.h.game.GuiService.SelectedObject
						if sel then
							activate(c, sel)
						end
					end,
				})
			end
		end
	end
	-- Ranch › Style : chaque sous-liste (Selle, Traînée, Titre, Thème, Drapeau, Tenues)
	for _, kind in { "trail", "title", "theme", "flag", "outfits" } do
		table.insert(list, {
			id = "panel.Ranch.style." .. kind,
			run = function(c)
				open(c, "Ranch", "style")
				local win = c.PC.window("Ranch")
				local b = win and win:FindFirstChild("Kind_" .. kind, true)
				if b then
					activate(c, b)
				end
			end,
		})
	end
	-- listes longues : la croix ↓ jusqu'au bout (rangées sous la ligne de flottaison)
	for _, entry in
		{ { "Settings", "" }, { "Ranch", "pens" }, { "Squishydex", "species" }, { "Objectives", "plop" } }
	do
		local panel, tab = entry[1], entry[2]
		table.insert(list, {
			id = "panel." .. panel .. (if tab ~= "" then "." .. tab else "") .. ".end",
			run = function(c)
				open(c, panel, if tab ~= "" then tab else nil)
				for _ = 1, 14 do
					Gamepad.tap(c.h, Enum.KeyCode.DPadDown)
					frames(c, 2, 0.2)
				end
			end,
		})
	end
	-- Objectifs : les 18 sortes d'objectifs du jour (3 par écran, fait / réclamé / en cours)
	for k = 0, 5 do
		table.insert(list, {
			id = string.format("panel.Objectives.today.set%d", k + 1),
			run = function(c)
				local day = math.floor(c.Clock.now() / 86400)
				local entries = {}
				for j = 1, 3 do
					local id = 3 * k + j
					table.insert(entries, {
						id = id,
						p = if j == 1 then 9999 else 1,
						done = j == 1,
						claimed = j == 2 and k % 2 == 0,
					})
				end
				c.h:fireClient(
					REMOTES .. "DataPatch",
					{ objectives = { day = day, list = entries, rerolls = 0, allClaimed = false } },
					{}
				)
				frames(c, 2, 0.1)
				open(c, "Objectives", "today")
			end,
		})
	end

	-- États particuliers des panneaux
	table.insert(list, {
		id = "panel.Objectives.today.alldone",
		run = function(c)
			local day = math.floor(c.Clock.now() / 86400)
			local entries = {}
			for j, id in { 1, 7, 14 } do
				table.insert(entries, { id = id, p = 9999, done = true, claimed = j ~= 2 })
			end
			c.h:fireClient(REMOTES .. "DataPatch", {
				objectives = { day = day, list = entries, rerolls = 1, allClaimed = false },
				lastFeedDay = day,
			}, {})
			frames(c, 2, 0.1)
			open(c, "Objectives", "today")
		end,
	})
	table.insert(list, {
		id = "panel.Objectives.today.claimedall",
		run = function(c)
			local day = math.floor(c.Clock.now() / 86400)
			local entries = {}
			for _, id in { 2, 8, 15 } do
				table.insert(entries, { id = id, p = 9999, done = true, claimed = true })
			end
			c.h:fireClient(
				REMOTES .. "DataPatch",
				{ objectives = { day = day, list = entries, rerolls = 1, allClaimed = true } },
				{}
			)
			frames(c, 2, 0.1)
			open(c, "Objectives", "today")
		end,
	})
	table.insert(list, {
		id = "panel.Objectives.plop.fed",
		run = function(c)
			c.h:fireClient(REMOTES .. "DataPatch", { lastFeedDay = math.floor(c.Clock.now() / 86400) }, {})
			frames(c, 2, 0.1)
			open(c, "Objectives", "plop")
		end,
	})
	table.insert(list, {
		id = "panel.Leaderboards.empty",
		run = function(c)
			local boards = {}
			for _, cat in { "stamps", "combo", "catchScore", "helpful", "generous" } do
				boards[cat] = { top = {}, server = {}, mine = 0, minePrev = 0, myServerRank = 0 }
			end
			c.h:fireClient(REMOTES .. "LeaderboardState", { week = 3, boards = boards })
			frames(c, 2, 0.1)
			open(c, "Leaderboards", "stamps")
		end,
	})
	table.insert(list, {
		id = "panel.Leaderboards.me",
		run = function(c)
			leaderboards(c, state == "huge")
			-- moi dans le top 10 mondial
			local boards = {}
			for _, cat in { "stamps", "combo", "catchScore", "helpful", "generous" } do
				local top = {}
				for r = 1, 10 do
					table.insert(top, {
						rank = r,
						userId = if r == 3 then c.h.localPlayer.UserId else 3000 + r,
						name = if r == 3 then Screens.LONG_NAME else Screens.LONG_NAME_2,
						value = 9.87654321e12 / r,
					})
				end
				boards[cat] =
					{ top = top, server = top, mine = 9.87654321e12 / 3, minePrev = 1e12, myServerRank = 3 }
			end
			c.h:fireClient(REMOTES .. "LeaderboardState", { week = 3, boards = boards })
			frames(c, 2, 0.1)
			open(c, "Leaderboards", "combo")
		end,
	})
	table.insert(list, {
		id = "panel.Shop.party.active",
		event = true,
		run = function(c)
			unstub(c)
			eventStub(c, c.Clock.now(), {
				boost = { kind = "squish", untilT = c.Clock.now() + 3599, byName = Screens.LONG_NAME_2 },
			})
			open(c, "Shop", "party")
		end,
	})
	table.insert(list, {
		id = "panel.Settings.owner",
		run = function(c)
			c.h.game.PrivateServerOwnerId = c.h.localPlayer.UserId
			open(c, "Settings")
			for _ = 1, 14 do
				Gamepad.tap(c.h, Enum.KeyCode.DPadDown)
				frames(c, 2, 0.2)
			end
			c.h.game.PrivateServerOwnerId = 0
		end,
	})
	table.insert(list, {
		id = "panel.Ranch.fuse.chooseB",
		run = function(c)
			open(c, "Ranch", "fuse")
			local win = c.PC.window("Ranch")
			local chooseA = win and win:FindFirstChild("ChooseA", true)
			if chooseA then
				activate(c, chooseA)
				local sel = c.h.game.GuiService.SelectedObject
				if sel then
					activate(c, sel)
				end
			end
		end,
	})
	table.insert(list, {
		id = "panel.Ranch.sell.confirm",
		run = function(c)
			open(c, "Ranch", "sell")
			local sel = c.h.game.GuiService.SelectedObject
			if sel then
				activate(c, sel)
			end
			local win = c.PC.window("Ranch")
			local sell = win and win:FindFirstChild("Sell", true)
			if sell and sell:IsA("GuiButton") then
				activate(c, sell)
			end
		end,
	})

	-- Ranch › Enclos › Taille : le tri change (rareté, revenu)
	table.insert(list, {
		id = "panel.Ranch.pens.sort",
		run = function(c)
			open(c, "Ranch", "pens")
			local win = c.PC.window("Ranch")
			local sort = win and win:FindFirstChild("Sort", true)
			if sort then
				activate(c, sort)
			end
		end,
	})
	table.insert(list, {
		id = "panel.Ranch.pens.sort2",
		run = function(c)
			open(c, "Ranch", "pens")
			local win = c.PC.window("Ranch")
			local sort = win and win:FindFirstChild("Sort", true)
			if sort then
				activate(c, sort)
			end
		end,
	})
	-- Squishydex › Guide défilé jusqu'au bout (règles du BOOP RUSH)
	table.insert(list, {
		id = "panel.Squishydex.guide.end",
		run = function(c)
			open(c, "Squishydex", "guide")
			local win = c.PC.window("Squishydex")
			local guide = win and win:FindFirstChild("Guide", true)
			if guide then
				c.h.game.GuiService.SelectedObject = guide
				c.h:settle(1)
				for _ = 1, 12 do
					Gamepad.tap(c.h, Enum.KeyCode.DPadDown)
					frames(c, 2, 0.2)
				end
			end
		end,
	})
	-- Ranch › Enclos › Ranger : l'aperçu de la vente groupée
	table.insert(list, {
		id = "panel.Ranch.pens.tidy",
		run = function(c)
			open(c, "Ranch", "pens")
			local win = c.PC.window("Ranch")
			local tidy = win and win:FindFirstChild("Tidy", true)
			if tidy then
				activate(c, tidy)
			end
		end,
	})
	-- Réglages en mode Rush
	table.insert(list, {
		id = "panel.Settings.rush",
		run = function(c)
			c.h:fireClient(REMOTES .. "DataPatch", {
				mode = {
					rush = true,
					chosen = true,
					changedAt = 0,
					cardShown = true,
					postBoopCardShown = true,
				},
			}, {})
			frames(c, 2, 0.1)
			open(c, "Settings")
		end,
	})

	-- Aperçu du Grand Splorch : « Détails »
	table.insert(list, {
		id = "panel.SplorchPreview.details",
		run = function(c)
			open(c, "SplorchPreview")
			local win = c.PC.window("SplorchPreview")
			local details = nil
			if win then
				for _, d in win:GetDescendants() do
					if d:IsA("GuiButton") and string.find(d.Name, "Details", 1, true) then
						details = d
						break
					end
				end
			end
			if details then
				activate(c, details)
			end
		end,
	})
	return list
end

-- Cartes (affichées, puis rouvertes depuis le « ! »), carte du choix Rush / Cozy, écran de retour
local function cardScreens()
	local list = {}
	local function celebrate(id, kind, data)
		table.insert(list, {
			id = "card." .. id,
			run = function(c)
				closeAll(c)
				flushAll(c)
				c.h:fireClient(REMOTES .. "Celebrate", { kind = kind, data = data(c) })
				frames(c, 8, 0.1)
			end,
		})
	end
	celebrate("booped", "booped", function(c)
		return { uid = "u1", species = longestSpecies(c), booperId = c.players[1].UserId }
	end)
	celebrate("postBoop", "ownerReturn", function(c)
		return {
			uid = "u1",
			species = longestSpecies(c),
			coins = 1.23456789e18,
			firstBoop = true,
			catcherId = c.players[1].UserId,
			catcherName = Screens.LONG_NAME_2,
		}
	end)
	celebrate("objectives", "objectivesCard", function()
		return { day = 1 }
	end)
	celebrate("newObjectives", "newObjectives", function()
		return { day = 2 }
	end)
	celebrate("dexNew", "dexNew", function(c)
		return { species = longestSpecies(c), mutation = longestMutation(c), star = 5 }
	end)
	celebrate("sleepy", "sleepy", function()
		return { minutes = 59 }
	end)
	table.insert(list, {
		id = "card.mode",
		run = function(c)
			closeAll(c)
			flushAll(c)
			unstub(c)
			ranchStub(c, "cozy")
			eventStub(c, c.Clock.now())
			c.h:fireClient(REMOTES .. "ModePrompt", {})
			frames(c, 10, 0.2)
			-- garde d'entrée de 0,6 s passée : boutons actifs
			frames(c, 4, 0.3)
		end,
	})
	table.insert(list, {
		id = "card.reopened",
		run = function(c)
			closeAll(c)
			flushAll(c)
			unstub(c)
			c.h:fireClient(REMOTES .. "Celebrate", {
				kind = "booped",
				data = { uid = "u1", species = longestSpecies(c), booperId = c.players[1].UserId },
			})
			frames(c, 4, 0.1)
			flushCards(c)
			-- la carte « booped » rangée (et non une carte plus ancienne)
			local chosen = nil
			for _, card in c.Cards.pending() do
				if card.kind == "booped" then
					chosen = card
				end
			end
			if chosen then
				c.Cards.open(chosen.id)
				frames(c, 6, 0.1)
			end
		end,
	})
	-- carte « Garder ton clip ? » (VFXController, appareil qui filme)
	table.insert(list, {
		id = "card.clip",
		run = function(c)
			closeAll(c)
			flushAll(c)
			c.Cards.push({
				id = "",
				kind = "clip",
				blocking = false,
				data = { save = function() end, share = function() end },
			})
			frames(c, 8, 0.1)
		end,
	})
	-- carte « revient toujours » rouverte depuis le « ! »
	table.insert(list, {
		id = "card.reopened.postBoop",
		run = function(c)
			closeAll(c)
			flushAll(c)
			c.h:fireClient(REMOTES .. "Celebrate", {
				kind = "ownerReturn",
				data = { uid = "p11", species = longestSpecies(c), coins = 1.23456789e18, firstBoop = true },
			})
			frames(c, 4, 0.1)
			flushCards(c)
			local chosen = nil
			for _, card in c.Cards.pending() do
				if card.kind == "postBoop" then
					chosen = card
				end
			end
			if chosen then
				c.Cards.open(chosen.id)
				frames(c, 6, 0.1)
			end
		end,
	})
	-- lot B3, étape 5 : états de la v1.3 que les scénarios ne montraient pas (TextFitKeysPending [auto])
	-- nouvelle espèce sans mutation (« NOUVEAU ! … »)
	celebrate("dexNew.plain", "dexNew", function(c)
		return { species = longestSpecies(c), mutation = 0, star = 1 }
	end)
	-- « Garder ton clip ? » rouverte depuis « ! » : Garder, Partager, Fermer
	table.insert(list, {
		id = "card.reopened.clip",
		run = function(c)
			closeAll(c)
			flushAll(c)
			c.Cards.push({
				id = "",
				kind = "clip",
				blocking = false,
				data = { save = function() end, share = function() end },
			})
			frames(c, 4, 0.1)
			flushCards(c)
			for _, card in c.Cards.pending() do
				if card.kind == "clip" then
					c.Cards.open(card.id)
				end
			end
			frames(c, 6, 0.1)
		end,
	})
	-- « revient toujours » d'un boopeur connu, rouverte : Continuer, Mode Cozy, Pas ce joueur
	table.insert(list, {
		id = "card.reopened.postBoop.refuse",
		run = function(c)
			closeAll(c)
			flushAll(c)
			unstub(c)
			local booper = c.players[1].UserId
			c.h:fireClient(REMOTES .. "Celebrate", {
				kind = "booped",
				data = { uid = "u9", species = longestSpecies(c), booperId = booper },
			})
			c.h:fireClient(REMOTES .. "Celebrate", {
				kind = "ownerReturn",
				data = {
					uid = "u9",
					species = longestSpecies(c),
					coins = 1.23456789e18,
					firstBoop = true,
					catcherId = booper,
					catcherName = Screens.LONG_NAME_2,
				},
			})
			frames(c, 4, 0.1)
			flushCards(c)
			for _, card in c.Cards.pending() do
				if card.kind == "postBoop" then
					c.Cards.open(card.id)
				end
			end
			frames(c, 6, 0.1)
		end,
	})
	-- carte du choix Rush / Cozy à la fin de sa petite animation : « … avec des cadeaux ! »
	table.insert(list, {
		id = "card.mode.gifts",
		run = function(c)
			closeAll(c)
			flushAll(c)
			unstub(c)
			ranchStub(c, "cozy")
			eventStub(c, c.Clock.now())
			c.h:fireClient(REMOTES .. "ModePrompt", {})
			frames(c, 10, 0.2)
			frames(c, 12, 0.2)
		end,
	})
	-- absence de moins d'une heure : « 12 min »
	table.insert(list, {
		id = "return.minutes",
		run = function(c)
			closeAll(c)
			flushAll(c)
			c.h:fireClient(REMOTES .. "Celebrate", {
				kind = "return",
				data = {
					seconds = 720,
					uid = "u1",
					species = longestSpecies(c),
					grew = 1.23456789e18,
					pot = 9.87654321e17,
					splorchReady = false,
					nearlyReady = false,
				},
			})
			frames(c, 30, 0.1)
		end,
	})
	for _, variant in { { "ready", true, false }, { "nearly", false, true }, { "plain", false, false } } do
		table.insert(list, {
			id = "return." .. variant[1],
			run = function(c)
				closeAll(c)
				flushAll(c)
				c.h:fireClient(REMOTES .. "Celebrate", {
					kind = "return",
					data = {
						seconds = 43199,
						uid = "u1",
						species = longestSpecies(c),
						grew = 1.23456789e18,
						pot = 9.87654321e17,
						splorchReady = variant[2],
						nearlyReady = variant[3],
					},
				})
				frames(c, 30, 0.1)
			end,
		})
	end
	return list
end

-- Bannières : toutes les clés banner.* (variables les plus longues)
function Screens.bannerScreens(c)
	local out = {}
	local kinds = {}
	for key in c.Strings.en do
		local kind = string.match(key, "^banner%.([%w]+)$")
		if kind then
			table.insert(kinds, kind)
		end
	end
	table.sort(kinds)
	for _, kind in kinds do
		table.insert(out, {
			id = "banner." .. kind,
			run = function(cc)
				closeAll(cc)
				flushAll(cc)
				cc.Banners.show({
					kind = kind,
					args = {
						name = Screens.LONG_NAME_2,
						userId = cc.players[1].UserId,
						species = longestSpecies(cc),
						mutation = longestMutation(cc),
						odds = 1000000,
						n = 5,
						threshold = 1e15,
					},
					priority = 1,
				})
				frames(cc, 4, 0.1)
			end,
		})
	end
	return out
end

-- Cote d'un tampon des effets telle que le jeu l'écrit (VFXController : Util.number de d.oneIn) :
-- la plus rare que Logic/Odds peut donner aux vrais réglages (toutes qualités de cuve, buses, lune) —
-- flop, glitch, rainbow : cette mutation, toute rareté ; secretTag : Mythique ou Secret sans ces trois
-- mutations. Relecture B1 : le scénario écrivait « 1 000 000 000 » en dur (espaces ordinaires), un
-- texte que le jeu n'écrit jamais (« 2,00B »), et l'outil y voyait une coupure « 1 000 / 000 »
local function stampOdds(c, kind: string): string
	local Odds = c.h:require("ReplicatedStorage.Shared.Logic.Odds")
	local Balance = c.h:require("ReplicatedStorage.Shared.Config.Balance")
	local special = { flop = true, glitch = true, rainbow = true }
	local mutations = {}
	for id, def in c.Mutations.ById do
		if def.key == kind or (kind == "secretTag" and not special[def.key]) then
			table.insert(mutations, id)
		end
	end
	local rarities = { 1, 2, 3, 4, 5, 6, 7 }
	if kind == "secretTag" then
		table.insert(mutations, c.Mutations.NONE)
		rarities = { 6, 7 }
	end
	local best = 0
	for _, r in rarities do
		for _, m in mutations do
			for q = 1, #Balance.Vat.Quality do
				for n = 0, 8 do
					for _, moon in { false, true } do
						best = math.max(best, Odds.oneIn(r, m, q, n, moon))
					end
				end
			end
		end
	end
	return c.h:require(CLIENT .. "World.Util").number(best)
end

-- Valeurs d'essai des variables de textes (les plus longues plausibles)
local NUMBER_VARS = {
	amount = 1.23456789e18,
	cost = 1.23456789e18,
	missing = 1.23456789e18,
	coins = 1.23456789e18,
	price = 1499,
	total = 98765,
	n = 9876,
	count = 9876,
	max = 9999,
	level = 12,
	stars = 5,
	rank = 12,
	minutes = 59,
	seconds = 59,
	hours = 23,
	day = 7,
	days = 999,
	odds = 1000000,
	fame = 98765,
	size = 1.23456789e18,
	points = 98765,
	target = 99999,
}

-- Écran Améliorations (lot B2) : pires valeurs PLAUSIBLES de ses variables (GDD §10.7.7 : « Record
-- 400 », « Boucle 10 », « 40/40 », « 99,9 Nvvg », « Max (×40) », « ×2,000 », « 14 studs ») ; une
-- fonction (Format du client, langue) ou un nombre (BigNumber)
local UPGRADE_PREFIXES = { "upgrades.", "workshop.", "helper.", "hud.memory" }
local UPGRADE_VARS = {
	r = 400,
	a = 40,
	b = 40,
	m = 40,
	price = 9.99e94,
	amount = 9.99e94,
	s = function(F, lang)
		return F.decimal(12, lang, 1) -- « 12,0 » (intervalle d'une Plopette, École 0)
	end,
	f = function(F, lang)
		return F.decimal(1.25, lang) -- Souvenir « ×1,25 »
	end,
	vat = 8,
	vatMax = 8,
	tier = 6,
	tierMax = 6,
	quality = 8,
	speed = 10,
	nozzles = 6,
}
-- {n} des unités : la plus large valeur de chaque unité (Balance : Aimant 14 studs, Pot 31 %…)
local UPGRADE_UNIT_N = {
	["upgrades.unit.mult"] = function(F, lang)
		return F.decimal(1.975, lang, 3)
	end,
	["upgrades.unit.hours"] = function(F, lang)
		return F.decimal(13, lang)
	end,
	["upgrades.unit.seconds"] = function(F, lang)
		return F.decimal(12, lang, 1)
	end,
	["upgrades.unit.studs"] = function(F, lang)
		return F.decimal(14, lang)
	end,
	["upgrades.unit.levels"] = function(F)
		return F.count(25)
	end,
	["upgrades.unit.percent"] = function(F, lang)
		return F.decimal(31, lang)
	end,
	["upgrades.unit.count"] = function(F, lang)
		return F.percent(10, lang)
	end,
}

-- Pire valeur d'une variable pour UNE clé (avant UPGRADE_VARS) : gain des Décorations annoncé par
-- l'aperçu Max (18 niveaux d'un coup, A = 1 : 18 × 5 % = « 90,0 » ; lot B2, étape 5)
local UPGRADE_KEY_VARS = {
	["upgrades.effect.incomeTotal"] = {
		a = function(F, lang)
			return F.decimal(90, lang, 1)
		end,
	},
}

-- Texte le plus long des déblocages de la table du §4.29 (variable {unlock} de workshop.risesDetail)
local function longestUnlock(c, lang)
	local L = c.Localization or c.h:require("ReplicatedStorage.Shared.Localization")
	local Visuals = c.h:require("ReplicatedStorage.Shared.Config.Visuals")
	local best = ""
	for _, row in Visuals.RecordTable do
		for _, tile in row.unlocks do
			local vars = {}
			for k, v in tile.vars or {} do
				vars[k] = if type(v) == "string" then L.get(lang, v) else tostring(v)
			end
			local text = L.get(lang, tile.key, vars)
			if utf8.len(text) and utf8.len(text) > (utf8.len(best) or 0) then
				best = text
			end
		end
	end
	return best
end

function Screens.varsFor(c, key, lang)
	lang = lang or c.lang
	local vars = {}
	local strings = c.Strings[lang] or c.Strings.en
	local template = strings[key] or c.Strings.en[key] or ""
	local BN = c.BigNumber or c.h:require("ReplicatedStorage.Shared.Logic.BigNumber")
	c.BigNumber = BN
	local upgrade = false
	for _, prefix in UPGRADE_PREFIXES do
		if string.sub(key, 1, #prefix) == prefix then
			upgrade = true
		end
	end
	local keyVars = if upgrade then UPGRADE_KEY_VARS[key] else nil
	for name in string.gmatch(template, "{(%w+)}") do
		local worst = if upgrade then UPGRADE_VARS[name] else nil
		if keyVars and keyVars[name] ~= nil then
			worst = keyVars[name]
		elseif upgrade and name == "n" and UPGRADE_UNIT_N[key] then
			worst = UPGRADE_UNIT_N[key]
		elseif upgrade and name == "n" then
			worst = 40
		end
		if upgrade and name == "unlock" then
			vars[name] = longestUnlock(c, lang)
		elseif type(worst) == "function" then
			vars[name] = worst(c.h:require(CLIENT .. "UI.Format"), lang)
		elseif type(worst) == "number" then
			vars[name] = BN.abbreviate(worst, lang)
		elseif NUMBER_VARS[name] then
			vars[name] = BN.abbreviate(NUMBER_VARS[name], lang)
		elseif name == "name" or name == "catcher" or name == "booper" then
			vars[name] = Screens.LONG_NAME_2
		elseif name == "species" then
			local def = c.Species.ById[c.longestSpeciesId or 1]
			vars[name] = strings["species." .. def.key] or def.name
		elseif name == "time" then
			vars[name] = "59:59"
		else
			vars[name] = "Grand Splorch"
		end
	end
	return vars
end

function Screens.keysWithPrefix(c, prefix)
	local keys = {}
	for key in c.Strings.en do
		if string.sub(key, 1, #prefix) == prefix then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	return keys
end

-- Écrans « feedback.N » : quelques clés feedback.* affichées dans l'emplacement de message (une à la
-- fois) ; TextFit_keys vérifie TOUTES les autres dans la même boîte
function Screens.feedbackScreens(c)
	local out = {}
	local keys = Screens.keysWithPrefix(c, "feedback.")
	-- les plus longues dans la langue de l'écran d'abord
	table.sort(keys, function(a, b)
		local la = utf8.len(c.Strings[c.lang][a] or "") or 0
		local lb = utf8.len(c.Strings[c.lang][b] or "") or 0
		if la ~= lb then
			return la > lb
		end
		return a < b
	end)
	for i = 1, math.min(4, #keys) do
		local key = keys[i]
		table.insert(out, {
			id = string.format("feedback.longest%d", i),
			run = function(cc)
				closeAll(cc)
				flushAll(cc)
				cc.h:fireClient(
					REMOTES .. "Feedback",
					{ key = key, vars = Screens.varsFor(cc, key), tone = "info" }
				)
				frames(cc, 4, 0.1)
			end,
		})
	end
	return out
end

-- Accueil : HUD à chaque étape (consigne du moment)
local function onboardingScreens()
	local list = {}
	for step = 1, 11 do
		table.insert(list, {
			id = string.format("onboarding.step%02d", step),
			run = function(c)
				closeAll(c)
				flushAll(c)
				unstub(c)
				c.h:fireClient(
					REMOTES .. "DataPatch",
					{ onboarding = { step = step, done = false, demoDone = step > 4 } },
					{}
				)
				c.h:fireClient(REMOTES .. "Celebrate", { kind = "onboarding", data = { step = step } })
				frames(c, 10, 0.5)
				refreshHud(c)
			end,
		})
	end
	return list
end

-- ---------------------------------------------------------------------------------------------
-- Écran Améliorations (lot B2, étape 2) : instantanés v2.0 fabriqués depuis le profil témoin
-- tests/fixtures/profiles/v2.json (interrupteurs v2.0 ouverts DANS le scénario, jamais dans le jeu
-- livré) ; chaque écran pose son instantané (version croissante) et les attributs du ranch du joueur,
-- ouvre l'écran sur son onglet et son mode, et sélectionne la ligne dont le bandeau est à montrer
-- ---------------------------------------------------------------------------------------------

local V2_WITNESS = nil
local function v2Witness()
	if V2_WITNESS == nil then
		V2_WITNESS = serde.decode("json", fs.readFile("tests/fixtures/profiles/v2.json"))
	end
	return deepCopy(V2_WITNESS)
end

-- Instantané v2.0 du profil témoin modifié par `edit` (version suivante de ce client)
function Screens.upgradeSnapshot(c, edit)
	local UM = c.h:require("ReplicatedStorage.Shared.Logic.UpgradeMath")
	local Features = c.h:require("ReplicatedStorage.Shared.Config.Features")
	local flags = {}
	for k, v in Features.Defaults do
		flags[k] = if type(v) == "boolean" then true else v
	end
	local p = v2Witness()
	if edit then
		edit(p, UM)
	end
	c.upgradeVersion = (c.upgradeVersion or 0) + 1
	return UM.snapshot(p, flags, c.upgradeVersion)
end

-- Modèle Wobbleton/Ranches/1 (ranch du joueur, Screens.ranchStub) et ses attributs v2.0 du serveur
function Screens.myRanchModel(c, attrs)
	local function child(parent, name, class)
		local f = parent:FindFirstChild(name)
		if f == nil then
			f = MockInstance.new(class)
			f.Name = name
			f.Parent = parent
		end
		return f
	end
	local world = child(c.h.workspace, "Wobbleton", "Folder")
	local model = child(child(world, "Ranches", "Folder"), "1", "Model")
	for k, v in attrs do
		model:SetAttribute(k, v)
	end
	return model
end

-- Amène l'écran Améliorations dans un état : opts.edit (profil témoin), opts.ranch (attributs),
-- opts.wait (secondes de jeu avant l'ouverture), opts.tab, opts.mode (appuis sur □), opts.select
-- (ligne sélectionnée : son bandeau) ; achats (étape 3) : opts.hold (secondes de ✕ tenu sur la
-- sélection ; moins de 0,6 : relâché trop tôt), opts.after (secondes de jeu après le maintien :
-- 3,2 = « Réessaie »), opts.answer(c, args, UM) → réponse UpgradeResult au dernier BuyUpgrade envoyé,
-- opts.settle (secondes de jeu après la réponse : 2 = retour chiffré passé, l'état revient)
local function upgradesState(c, opts)
	-- ✕ resté enfoncé par l'écran précédent (anneau à mi-maintien) : relâché d'abord
	if c.padHeld then
		c.padHeld = nil
		Gamepad.release(c.h, Enum.KeyCode.ButtonA)
		frames(c, 2, 0.1)
	end
	closeAll(c)
	flushAll(c)
	Screens.myRanchModel(c, opts.ranch or { HelperMode = "active", AscendReady = false })
	c.h:fireClient(REMOTES .. "DataPatch", { upgradeSnapshot = Screens.upgradeSnapshot(c, opts.edit) }, {})
	frames(c, 2, 0.1)
	if opts.wait then
		c.Clock.advance(opts.wait)
		frames(c, 2, 0.1)
	end
	open(c, "Upgrades", opts.tab)
	local Up = c.h:require(CLIENT .. "UI.Panels.Upgrades")
	for _ = 1, opts.mode or 0 do
		Up.cycleMode()
	end
	if opts.select then
		local obj = nil
		if type(opts.select) == "number" then
			obj = Up._card(opts.select)
		elseif string.sub(opts.select, 1, 5) == "card:" then
			-- carte du Conseillé par sa famille (« card:ascend » : la carte Jelly Ascend)
			local i = table.find(Up._cards(), string.sub(opts.select, 6))
			obj = if i then Up._card(i) else nil
		else
			obj = Up._row(opts.select)
		end
		if obj then
			c.h.game.GuiService.SelectedObject = obj
		end
	end
	if opts.holding then
		-- anneau à mi-maintien : ✕ tenu `holding` s, PAS relâché (l'écran suivant le relâche)
		frames(c, 5, 0.1)
		Gamepad.press(c.h, Enum.KeyCode.ButtonA)
		c.padHeld = true
		frames(c, math.max(1, math.floor(opts.holding * 30 + 0.5)), 1 / 30)
		return
	end
	if opts.hold then
		-- garde d'un focus changé (0,4 s) passée, puis ✕ tenu et relâché
		frames(c, 5, 0.1)
		Gamepad.press(c.h, Enum.KeyCode.ButtonA)
		frames(c, math.max(1, math.floor(opts.hold * 30 + 0.5)), 1 / 30)
		Gamepad.release(c.h, Enum.KeyCode.ButtonA)
		frames(c, 3, 1 / 30)
		if opts.after then
			frames(c, math.max(1, math.floor(opts.after * 10 + 0.5)), 0.1)
		end
		if opts.answer then
			local sent = TvAudit.sent(c.h, "BuyUpgrade")
			local args = sent[#sent]
			if args then
				local UM = c.h:require("ReplicatedStorage.Shared.Logic.UpgradeMath")
				c.h:fireClient(REMOTES .. "UpgradeResult", opts.answer(c, args, UM))
				c.h:settle(1)
			end
		end
		if opts.settle then
			-- retour chiffré passé (1,5 s) : l'état de la ligne ou de la carte revient
			frames(c, math.max(1, math.floor(opts.settle * 10 + 0.5)), 0.1)
		end
	end
	frames(c, 6, 0.1)
end
Screens.upgradesState = upgradesState

-- Réponse du serveur fabriquée (étape 3) : `to` niveaux après (nil : refus), `reason`, `spent`, et le
-- profil témoin de l'instantané joint (`edit`)
local function upgradeAnswer(opts)
	return function(c, args, UM)
		local id, from = args[1], args[3]
		local to = if opts.levels then from + opts.levels else from
		return {
			id = id,
			from = from,
			to = to,
			spent = if to > from then opts.spent or 9.99e94 else 0,
			currency = UM.currency(id),
			reason = opts.reason,
			snapshot = Screens.upgradeSnapshot(c, opts.edit),
		}
	end
end

-- Profils de l'écran (champs du profil témoin v2 : R = boucle r, bestR = Record R, ascend = A)
local function tiles(p, t)
	for k, v in t do
		p.tiles[k] = v
	end
end

-- ---------------------------------------------------------------------------------------------
-- v2.0 (lot B2, étape 4) : HUD v2.0 et rail (groupe « hudv2 ») ; d'abord deux états de la v1.3
-- (pastilles de la puce Menu l'une sur l'autre, file au pire cas), puis l'instantané du serveur
-- arrive (DataPatch upgradeSnapshot, profil témoin v2) et le HUD v2.0 se construit
-- ---------------------------------------------------------------------------------------------

-- Monde v2.0 (lot B4) : textes du monde du ranch qui évolue, interrupteurs ouverts DANS le scénario
-- seulement (le client suit ce que le serveur montre). Étape 1 : étiquette de la dalle du Tapis Étoilé
-- (D11) allumée par le serveur au-delà du Tapis 12. Étape 5 : panneaux des ranchs (nom de 20 caractères,
-- couronne dessinée et Record R 400, « Jour 9 999 », badge boop, bouclier, ranch libre, « PRÊT ! »), dalle
-- du Tapis 1, Tapis Étoilé 13 et 20 (prix géants), plaque du titre avec la goutte du halo et 60, statue
-- (nom long et taille géante, puis vide), bulle « Boîte à dodo ! », panneau de la Prairie v2, kiosque de
-- Big Plop (étiquette et invite □ « Atelier ») ; le kiosque vient en dernier (instantané de l'écran
-- Améliorations : il reste jusqu'à la fin du groupe)
local function worldScreens()
	local list = {}
	local V2_ATTRS = { "BestR", "SplorchReady", "HaloOn", "Ascend", "Monuments", "TapisTier" }
	local function child(parent, name, class, size)
		local f = parent:FindFirstChild(name)
		if f == nil then
			f = MockInstance.new(class)
			f.Name = name
			if size then
				f.Size = size
			end
			f.Parent = parent
		end
		return f
	end
	local function ranchModelAt(c, slot)
		local world = child(c.h.workspace, "Wobbleton", "Folder")
		return child(child(world, "Ranches", "Folder"), tostring(slot), "Model")
	end
	-- monde de la scène : panneaux des 4 ranchs du stub, Cuve de mon ranch, attributs v2.0 retirés
	local function worldReset(c)
		closeAll(c)
		flushAll(c)
		unstub(c)
		for slot = 1, 4 do
			local model = ranchModelAt(c, slot)
			child(model, "Sign", "Part", Vector3.new(6, 2, 0.4))
			for _, name in V2_ATTRS do
				model:SetAttribute(name, nil)
			end
		end
		child(ranchModelAt(c, 1), "Vat", "Part", Vector3.new(4, 4, 4))
		local plaza = c.h.workspace.Wobbleton:FindFirstChild("Plaza")
		if plaza then
			plaza:Destroy()
		end
	end
	local function ranches(c, mine, second)
		c.seq = (c.seq or 0) + 1
		local mineRec = ranchPublic(c, 1, c.h.localPlayer.UserId, Screens.LONG_NAME, mine)
		c.h:fireClient(REMOTES .. "RanchSnapshot", {
			seq = c.seq,
			ranches = {
				["1"] = mineRec,
				["2"] = ranchPublic(c, 2, c.players[1].UserId, Screens.LONG_NAME_2, second),
				["3"] = ranchPublic(c, 3, c.players[4].UserId, "", { hidden = true, title = "" }),
				["4"] = ranchPublic(
					c,
					4,
					0,
					"",
					{ title = "", best = { s = 0, m = 0, z = 0, zg = 0 }, R = 0 }
				),
			},
			squishies = { ["1"] = {}, ["2"] = {}, ["3"] = {}, ["4"] = {} },
		})
		c.h:settle(2)
	end
	local function settle(c)
		frames(c, 20, 1 / 30)
		pcall(c.h:require(CLIENT .. "Controllers.LightingController").refresh)
		frames(c, 4, 1 / 30)
	end
	-- panneaux au pire cas : nom de 20 caractères, Record R 400 (BestR), « Jour 9 999 », Rush : badge boop
	-- sur le mien, bouclier sur le voisin ; ranch au nom caché (alias) ; ranch libre (« Ranch 4 »)
	table.insert(list, {
		id = "world.sign",
		run = function(c)
			worldReset(c)
			ranchModelAt(c, 1):SetAttribute("BestR", 400)
			ranches(
				c,
				{ mode = "rush", boopable = true, day = 9999, R = 0 },
				{ mode = "rush", shield = true, day = 9999, R = 400 }
			)
			settle(c)
		end,
	})
	-- « PRÊT ! » (world.ready) au bout du panneau : le pire cas (badge boop et « PRÊT ! ») et le calme
	table.insert(list, {
		id = "world.sign.ready",
		run = function(c)
			worldReset(c)
			local mine = ranchModelAt(c, 1)
			mine:SetAttribute("BestR", 400)
			mine:SetAttribute("SplorchReady", true)
			ranchModelAt(c, 2):SetAttribute("SplorchReady", true)
			ranches(
				c,
				{ mode = "rush", boopable = true, day = 9999, R = 0 },
				{ mode = "cozy", day = 9999, R = 400 }
			)
			settle(c)
		end,
	})
	local function starPad(c, R, A, star, snack)
		worldReset(c)
		local model = Screens.myRanchModel(c, {})
		local pads = model:FindFirstChild("Pads")
		if pads == nil then
			pads = MockInstance.new("Folder")
			pads.Name = "Pads"
			pads.Parent = model
		end
		local pad = pads:FindFirstChild("1")
		if pad == nil then
			pad = MockInstance.new("Part")
			pad.Name = "1"
			pad.Parent = pads
		end
		pad.Transparency = 0
		pad:SetAttribute("Maxed", false)
		local base = { snack = snack or 12, decor = 5, pens = 3, cozyBed = true, seen = 15 }
		local mine = table.clone(base)
		mine.star = star
		c.h:fireClient(
			REMOTES .. "DataPatch",
			{ version = 2, R = R, bestR = R, ascend = A, tiles = mine },
			{}
		)
		ranchStub(c, "cozy", { R = R, tiles = base })
		frames(c, 20, 1 / 30)
	end
	-- dalle du Tapis 1 (dalle de la v1.3) ; Tapis Étoilé 13 (premier niveau), 15, puis 20 au Record R et à
	-- A maximaux (prix géants de BigNumber)
	for _, case in
		{
			{ "world.pad.snack1", 0, 0, 0, 0 },
			{ "world.starPad.13", 12, 2, 0, 12 },
			{ "world.starPad", 12, 2, 3, 12 },
			{ "world.starPad.max", 400, 60, 7, 12 },
		}
	do
		table.insert(list, {
			id = case[1],
			run = function(c)
				starPad(c, case[2], case[3], case[4], case[5])
			end,
		})
	end
	-- plaque du titre au-dessus de ma tête : titre le plus long, goutte dessinée du halo et 60 Ascensions
	table.insert(list, {
		id = "world.title.halo",
		run = function(c)
			worldReset(c)
			local mine = ranchModelAt(c, 1)
			mine:SetAttribute("HaloOn", true)
			mine:SetAttribute("Ascend", 60)
			ranches(c, { day = 42 }, { day = 42 })
			settle(c)
		end,
	})
	-- statue de la place : nom de 20 caractères et taille géante, puis aucune (« Plus gros squishy »)
	for _, case in { { "world.statue", 1 }, { "world.statue.empty", 0 } } do
		table.insert(list, {
			id = case[1],
			run = function(c)
				worldReset(c)
				ranches(c, { day = 42 }, { day = 42 })
				local plaza = child(c.h.workspace.Wobbleton, "Plaza", "Folder")
				local statue = child(plaza, "Statue", "Part", Vector3.new(6, 6, 6))
				statue:SetAttribute("StatueSpecies", if case[2] == 1 then longestSpecies(c) else 0)
				statue:SetAttribute("StatueMutation", if case[2] == 1 then longestMutation(c) else 0)
				statue:SetAttribute("StatueSize", if case[2] == 1 then 9.99e35 else 0)
				statue:SetAttribute("StatueName", if case[2] == 1 then Screens.LONG_NAME_2 else "")
				settle(c)
			end,
		})
	end
	-- bulle « Boîte à dodo ! » sur ma Cuve : une naissance part au Dodo
	table.insert(list, {
		id = "world.dodo",
		run = function(c)
			worldReset(c)
			ranches(c, { day = 42 }, { day = 42 })
			-- message complet comme SquishyService (sans espèce, le texte qui monte serait « + » seul)
			c.h:fireClient(REMOTES .. "Celebrate", {
				kind = "hatch",
				data = {
					uid = 1,
					species = 1,
					rarity = 1,
					mutation = 0,
					oneIn = 1,
					isNew = false,
					at = "dodo",
				},
			})
			c.h:settle(1)
			frames(c, 3, 1 / 30)
		end,
	})
	-- Prairie v2 (D9, interrupteur Monuments) : le panneau « Coucou ! » du jardin du quartier nord
	table.insert(list, {
		id = "world.meadow.v2",
		run = function(c)
			worldReset(c)
			ranchModelAt(c, 1):SetAttribute("Monuments", 3)
			ranches(c, { day = 42 }, { day = 42 })
			settle(c)
		end,
	})
	-- kiosque de Big Plop (D21) : instantané de l'écran Améliorations (une ligne de l'Atelier visible),
	-- étiquette world.kiosk, puis le joueur à 4 studs du comptoir : invite □ « Atelier » (vraie cible de
	-- PromptController, glyphe de la plateforme)
	local function kioskScene(c)
		worldReset(c)
		ranches(c, { day = 42 }, { day = 42 })
		c.h:fireClient(REMOTES .. "DataPatch", { upgradeSnapshot = Screens.upgradeSnapshot(c) }, {})
		c.h:settle(1)
		settle(c)
		local kiosk = c.WorldLayout.plaza("kiosk")
		c.h:moveTo(c.h.localPlayer, kiosk + Vector3.new(4, 3, -4))
		frames(c, 12, 1 / 30)
		refreshHud(c)
	end
	table.insert(list, { id = "world.kiosk", run = kioskScene })
	-- relecture des écrans du lot B4 (B4-83) : □ sur le kiosque, à la manette (vraie entrée) : l'écran
	-- Améliorations ouvert sur l'Atelier, 1re ligne sous le focus ; puis ○ : retour au jeu en un appui (ni
	-- menu ni sélection), l'invite □ « Atelier » revenue
	table.insert(list, {
		id = "world.kiosk.open",
		run = function(c)
			kioskScene(c)
			c.Clock.advance(1)
			Gamepad.tap(c.h, Enum.KeyCode.ButtonX)
			c.h:settle(2)
			frames(c, 12, 1 / 30)
		end,
	})
	table.insert(list, {
		id = "world.kiosk.back",
		run = function(c)
			kioskScene(c)
			c.Clock.advance(1)
			Gamepad.tap(c.h, Enum.KeyCode.ButtonX)
			c.h:settle(2)
			frames(c, 12, 1 / 30)
			c.Clock.advance(1)
			Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
			c.h:settle(2)
			frames(c, 12, 1 / 30)
			refreshHud(c)
		end,
	})
	return list
end

local function hudV2Screens()
	local list = {}
	local DONE = { step = 11, done = true, demoDone = true }
	local function frozen(c)
		return { G = 0, g = 0, t = c.Clock.now() }
	end
	-- profil du client (squishies, boucle r) et instantané (édition du profil témoin v2) ; ranch :
	-- attributs v2.0 de Ranches/1 (AscendReady) ; ready : prestige de boucle prêt
	local function v2State(c, opts)
		Screens.myRanchModel(c, opts.ranch or { HelperMode = "active", AscendReady = false })
		local big = if opts.ready then 1e15 else 10
		-- pièces du HUD = celles de l'instantané (le serveur envoie les deux ensemble ; « Prêt ! » de la
		-- puce « Prochain achat » à côté d'un compteur cohérent)
		local snap = Screens.upgradeSnapshot(c, opts.edit)
		c.h:fireClient(REMOTES .. "DataPatch", {
			onboarding = DONE,
			coins = snap.coins,
			R = opts.r or 3,
			growth = frozen(c),
			squishies = {
				v2a = {
					s = 1,
					m = 0,
					st = 0,
					z = big,
					zg = 0,
					at = "pen",
					bf = 0,
					o = "",
					lk = false,
					b = 0,
					gd = 0,
				},
			},
		}, {})
		c.h:fireClient(REMOTES .. "DataPatch", { upgradeSnapshot = snap }, {})
		frames(c, 3, 0.1)
		ranchStub(c, "cozy", opts.ranchPublic)
		-- EventState « reçu » maintenant : l'attente de la file part de son eta (pire cas 59:59)
		c.WSC.EventChanged:Fire(eventStub(c, c.Clock.now(), opts.ev))
		if opts.pending then
			stub(c, c.h:require(CLIENT .. "UI.Cards"), "pending", function()
				return { { id = "hudv2", kind = "sleepy" } }
			end)
		end
	end
	local function regain(r, coins)
		return function(p)
			p.ascend = 1
			p.R = r
			p.bestR = 15
			p.coins = coins or 1
		end
	end
	local function add(id, setup)
		table.insert(list, hudScreen("hudv2." .. id, setup))
	end
	-- v1.3 : « ! » et jumeaux (2 chiffres) l'un sur l'autre à droite de la puce Menu ; file au pire
	-- cas (99e, 59:59) ; indicateurs avec leurs minutes (marque dessinée)
	table.insert(
		list,
		hudScreen("hud.badges", function(c)
			ranchStub(c, "rush", { shield = true })
			local now = c.Clock.now()
			local ev = eventStub(c, now, {
				boost = { kind = "wobble", untilT = now + 3599, byName = "" },
				spectacle = {
					queue = {
						{
							kind = "splorch",
							userId = 1,
							startAt = now + 3599,
							slot = 1,
							position = 99,
							eta = 3599,
						},
					},
				},
			})
			c.WSC.EventChanged:Fire(ev)
			c.HUD.setMenuBadges(true, 12)
		end)
	)
	-- HUD calme v2.0 : « Prochain achat » pas encore payable, puis « Prêt ! »
	add("calm", function(c)
		v2State(c, {
			edit = function(p)
				p.coins = 1
			end,
		})
	end)
	add("ready", function(c)
		v2State(c, {
			edit = function(p)
				p.coins = 1e30
			end,
		})
	end)
	-- très grands nombres : « … / … » au Record R le plus haut (prix de la boucle 400)
	add("huge", function(c)
		v2State(c, {
			edit = function(p)
				p.R = 400
				p.bestR = 400
				p.coins = 9.87e93
			end,
			r = 400,
		})
	end)
	-- Fame qui change : la pastille se montre 3 s (étoile et cœur dessinés)
	add("fame", function(c)
		v2State(c, {})
		c.h:fireClient(REMOTES .. "DataPatch", { fame = 987654 }, {})
		frames(c, 2, 0.1)
	end)
	-- rail v2.0 : 8 entrées (Grand Splorch prêt), 9 entrées (carte en attente), Jelly Ascend, Petit
	-- Splorch (maintien : glyphe ✕)
	local function rail(id, opts)
		table.insert(list, {
			id = "hudv2." .. id,
			run = function(c)
				closeAll(c)
				flushAll(c)
				unstub(c)
				v2State(c, opts)
				refreshHud(c)
				c.PC.openMenu()
				frames(c, 8, 0.1)
			end,
		})
	end
	rail("rail8", { ready = true })
	rail("rail9", { ready = true, pending = true })
	rail("railAscend", { ranch = { HelperMode = "active", AscendReady = true } })
	rail("railPetit", { ready = true, edit = regain(4), r = 4 })
	-- puces spéciales : JELLY ASCEND ! ; remontée : Souvenir et « Retour au record 4 / 15 », puis
	-- PETIT SPLORCH ! et « Prêt ! »
	add("ascendChip", function(c)
		v2State(c, { ranch = { HelperMode = "active", AscendReady = true } })
	end)
	add("regain", function(c)
		v2State(c, { edit = regain(4), r = 4 })
	end)
	add("petitChip", function(c)
		v2State(c, { edit = regain(4), r = 4, ready = true })
	end)
	-- file des grands spectacles : ma Jelly Ascend en tête (« Prochain · environ 0:12 »), puis au pire
	-- cas
	add("queueNext", function(c)
		local now = c.Clock.now()
		v2State(c, {
			ranch = { HelperMode = "active", AscendReady = true },
			ev = {
				spectacle = {
					queue = {
						{ kind = "ascend", userId = 1, startAt = now + 12, slot = 1, position = 1, eta = 12 },
					},
				},
			},
		})
	end)
	add("queueAscend", function(c)
		local now = c.Clock.now()
		v2State(c, {
			ranch = { HelperMode = "active", AscendReady = true },
			ev = {
				spectacle = {
					queue = {
						{
							kind = "ascend",
							userId = 1,
							startAt = now + 3599,
							slot = 1,
							position = 99,
							eta = 3599,
						},
					},
				},
			},
		})
	end)
	return list
end

local function upgradeScreens()
	local list = {}
	local function add(id, opts)
		table.insert(list, {
			id = "upgrades." .. id,
			run = function(c)
				upgradesState(c, opts)
			end,
		})
	end
	-- Conseillé : 3 familles (Tapis payable, puis les moins chères), Souvenir actif (r < Record R)
	add("suggested", {
		tab = "suggested",
		select = 1,
		edit = function(p)
			p.R = 5
			p.bestR = 12
			p.coins = 2500000
		end,
	})
	-- Conseillé : tout est au maximum (cartes neutres) ; Confettis 99 999 (le plus large entier brut)
	add("suggested.allMax", {
		tab = "suggested",
		select = 2,
		edit = function(p)
			tiles(p, {
				snack = 12,
				star = 8,
				decor = 18,
				pens = 14,
				cozyBed = true,
				gloves = 40,
				school = 20,
				monuments = 10,
			})
			p.R = 20
			p.bestR = 24
			p.confetti = 99999
		end,
	})
	-- Conseillé : Jelly Ascend prête et rien de payable depuis 5 min (carte « Jelly Ascend », N24)
	add("suggested.ascend", {
		tab = "suggested",
		select = "card:ascend",
		ranch = { HelperMode = "active", AscendReady = true },
		wait = 301,
		edit = function(p)
			tiles(
				p,
				{ snack = 12, star = 8, decor = 18, pens = 14, cozyBed = true, gloves = 40, school = 20 }
			)
			p.coins = 0
			p.R = 20
			p.bestR = 20
		end,
	})
	-- Ranch ×1 : Prêt (Tapis), Il manque (Gants), MAX (Enclos, Lit douillet), cadenas « Record 14 »
	-- (Monuments 4 : le 5e s'ouvre au Record R 14) ; bandeau : « Gardé pour toujours »
	add("ranch", {
		tab = "ranch",
		select = "pens",
		edit = function(p)
			tiles(p, { snack = 7, decor = 9, pens = 14, cozyBed = true, gloves = 30, monuments = 4 })
			p.coins = 4250000000
		end,
	})
	add("ranch.need", {
		tab = "ranch",
		select = "gloves",
		edit = function(p)
			tiles(p, { snack = 7, decor = 9, gloves = 30, monuments = 4 })
			p.coins = 1000
		end,
	})
	add("ranch.resets", {
		tab = "ranch",
		select = "snack",
		edit = function(p)
			tiles(p, { snack = 3 })
		end,
	})
	add("ranch.max", {
		tab = "ranch",
		select = "cozyBed",
	})
	add("ranch.locked", {
		tab = "ranch",
		select = "monument",
		edit = function(p)
			tiles(p, { snack = 12, monuments = 4 })
		end,
	})
	-- Ranch : boucle r = 3 après une Ascension, Tapis 12 + Étoilé au plafond de la boucle (« Boucle 6 »)
	add("ranch.loop", {
		tab = "ranch",
		select = "snack",
		edit = function(p)
			tiles(p, { snack = 12, star = 0 })
			p.R = 3
			p.bestR = 15
			p.ascend = 1
		end,
	})
	-- Ranch, premier jour : Gants « Record 1 », Lit « Record 3 », Monuments « Record 6 »
	add("ranch.early", {
		tab = "ranch",
		select = "gloves",
		edit = function(p)
			tiles(p, { snack = 2, decor = 0, pens = 0, cozyBed = false, gloves = 0, monuments = 0 })
			p.R = 0
			p.bestR = 0
			p.coins = 120
		end,
	})
	-- ×10 (10 niveaux payables), ×10 partiel (« 4 possibles »), Max (×n)
	add("ranch.x10", {
		tab = "ranch",
		select = "gloves",
		mode = 1,
		edit = function(p)
			tiles(p, { gloves = 5 })
			p.coins = 9.99e30
		end,
	})
	add("ranch.x10partial", {
		tab = "ranch",
		select = "decor",
		mode = 1,
		edit = function(p, UM)
			tiles(p, { decor = 2 })
			-- de quoi payer 4 niveaux sur 10 : « ×10 : 4 possibles · niveau 2 à 6 · … »
			local _, four = UM.bulk("decor", 2, 4, p.R, p.ascend, p.bestR)
			p.coins = four
		end,
	})
	add("ranch.max.preview", {
		tab = "ranch",
		select = "decor",
		mode = 2,
		edit = function(p)
			tiles(p, { decor = 2 })
			p.coins = 9.99e30
		end,
	})
	-- pires nombres : pièces 1e300 (prix au plafond), Gants 40/40, Record 400
	add("ranch.huge", {
		tab = "ranch",
		select = "gloves",
		edit = function(p)
			tiles(p, { snack = 11, decor = 17, gloves = 39 })
			p.R = 400
			p.bestR = 400
			p.coins = 1e300
			p.confetti = 100000
		end,
	})
	-- Plopettes : École, Pip … Puff présentes, Plume absente (« Atelier »), une sieste
	add("helpers", {
		tab = "helpers",
		select = "helper.pip",
		ranch = { HelperMode = "nap", AscendReady = false },
		edit = function(p)
			tiles(p, { school = 5 })
			p.bestR = 12
		end,
	})
	add("helpers.plume", {
		tab = "helpers",
		select = "helper.plume",
		edit = function(p)
			p.bestR = 12
		end,
	})
	add("helpers.active", {
		tab = "helpers",
		select = "school",
		edit = function(p)
			tiles(p, { school = 19 })
			p.bestR = 12
			p.coins = 1
		end,
	})
	-- Plopettes avant Pip (Record R 2) : cadenas sur l'onglet, « Record 2 »
	add("helpers.locked", {
		tab = "helpers",
		select = "helper.pop",
		edit = function(p)
			p.R = 1
			p.bestR = 1
		end,
	})
	-- Atelier : lignes prêtes, au maximum, cadenas « Ascension 1 » (Tremplin), Conseillé (étoiles)
	add("workshop", {
		tab = "workshop",
		select = "gift",
		edit = function(p)
			p.atelier = { 2, 1, 0, 0, 0, 0, 0, 0, 0, 0 }
			p.confetti = 139
		end,
	})
	add("workshop.ascend", {
		tab = "workshop",
		select = "springboard",
	})
	add("workshop.need", {
		tab = "workshop",
		select = "magnet",
		edit = function(p)
			p.confetti = 1
		end,
	})
	-- « Monte avec ton record » : prochain déblocage (Record R ≤ 20), puis la phrase de repli
	add("workshop.rises", {
		tab = "workshop",
		select = "risesWithRecord",
	})
	add("workshop.rises.top", {
		tab = "workshop",
		select = "risesWithRecord",
		edit = function(p)
			p.R = 20
			p.bestR = 24
		end,
	})
	-- « Pour le plaisir » : titre de section, 7 lignes, Déco perso (objet suivant dans le bandeau)
	add("workshop.fun", {
		tab = "workshop",
		select = "fun.palettes",
		edit = function(p)
			p.atelierCosmetics = { 5 }
			p.confetti = 5000
		end,
	})
	add("workshop.title", {
		tab = "workshop",
		select = "fun.title",
		edit = function(p)
			p.confetti = 5000
		end,
	})
	add("workshop.deco", {
		tab = "workshop",
		select = "decoShop",
		edit = function(p)
			p.atelier = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 3 }
			p.confetti = 5000
		end,
	})
	-- Achats (étape 3) : ligne « En cours », « Réessaie » (consigne du maintien, glyphe), retours dans la
	-- ligne (+1 niveau, +n niveaux, ×10 en partie « 4 sur 10 »), chaque raison de refus du serveur dans
	-- la ligne, relâché trop tôt ; carte du Conseillé : retour et refus ; Atelier : retour en Confettis
	local function rich(p)
		tiles(p, { decor = 2, gloves = 5 })
		p.coins = 9.99e94
	end
	local function boughtDecor(levels)
		return function(p)
			rich(p)
			tiles(p, { decor = 2 + levels })
		end
	end
	add("buy.ring", { tab = "ranch", select = "decor", edit = rich, holding = 0.35 })
	add("buy.ring.card", { tab = "suggested", select = 1, edit = rich, holding = 0.35 })
	add("buy.busy", { tab = "ranch", select = "decor", edit = rich, hold = 0.7 })
	add("buy.retry", { tab = "ranch", select = "decor", edit = rich, hold = 0.7, after = 3.2 })
	add("buy.hint", { tab = "ranch", select = "decor", edit = rich, hold = 0.3 })
	add("buy.one", {
		tab = "ranch",
		select = "decor",
		edit = rich,
		hold = 0.7,
		answer = upgradeAnswer({ levels = 1, edit = boughtDecor(1) }),
	})
	add("buy.many", {
		tab = "ranch",
		select = "gloves",
		edit = rich,
		mode = 1,
		hold = 0.7,
		answer = upgradeAnswer({
			levels = 10,
			edit = function(p)
				rich(p)
				tiles(p, { gloves = 15 })
			end,
		}),
	})
	add("buy.partial", {
		tab = "ranch",
		select = "decor",
		edit = rich,
		mode = 1,
		hold = 0.7,
		answer = upgradeAnswer({ levels = 4, edit = boughtDecor(4) }),
	})
	-- Tapis 12 acheté écran ouvert à r ≥ 6 (profil témoin : r = 12) : la même ligne continue avec le
	-- Tapis Étoilé, « 12/20 » et Prêt (relecture du lot B2, B2-65 : elle montrait « 12/12 » et MAX
	-- jusqu'à la réouverture)
	local function mat(snack)
		return function(p)
			tiles(p, { snack = snack, star = 0 })
			p.coins = 9.99e94
		end
	end
	add("buy.starContinues", {
		tab = "ranch",
		select = "snack",
		edit = mat(11),
		hold = 0.7,
		settle = 2,
		answer = upgradeAnswer({ levels = 1, edit = mat(12) }),
	})
	for _, reason in { "coins", "confetti", "locked", "maxed", "loopCap", "busy" } do
		add("buy.refused." .. reason, {
			tab = "ranch",
			select = "decor",
			edit = rich,
			hold = 0.7,
			answer = upgradeAnswer({ reason = "upgrades.refused." .. reason, edit = rich }),
		})
	end
	-- carte du Conseillé : la réponse garde la boucle de l'ouverture (r = 5, Record R 12) ; un instantané
	-- d'une autre boucle ferme l'écran (B2-66) et la capture ne montrait plus que le HUD (relecture des
	-- écrans du lot B2, B2-71)
	local function cardLoop(p)
		rich(p)
		p.R = 5
		p.bestR = 12
	end
	add("buy.card", {
		tab = "suggested",
		select = 1,
		edit = cardLoop,
		hold = 0.7,
		answer = function(c, args, UM)
			local id, from = args[1], args[3]
			return upgradeAnswer({
				levels = 1,
				edit = function(p)
					cardLoop(p)
					if type(p.tiles[id]) == "number" then
						p.tiles[id] = from + 1
					end
				end,
			})(c, args, UM)
		end,
	})
	add("buy.card.refused", {
		tab = "suggested",
		select = 2,
		edit = cardLoop,
		hold = 0.7,
		answer = upgradeAnswer({ reason = "upgrades.refused.busy", edit = cardLoop }),
	})
	add("buy.workshop", {
		tab = "workshop",
		select = "gift",
		edit = function(p)
			p.confetti = 99999
		end,
		hold = 0.7,
		answer = upgradeAnswer({
			levels = 1,
			spent = 99999,
			edit = function(p)
				p.atelier[1] = 1
				p.confetti = 0
			end,
		}),
	})
	-- Atelier vide (avant le Record R 1) : tout au cadenas « Record 1 »
	add("workshop.empty", {
		tab = "workshop",
		select = "startMat",
		edit = function(p)
			p.R = 0
			p.bestR = 0
		end,
	})

	-- -----------------------------------------------------------------------------------------
	-- Étape 5 : les états clés du GDD §10.8 qui manquaient ci-dessus (captures de référence,
	-- Screens.REFERENCE, Upgrades_Reference.spec) et les pires cas : libellés français les plus longs
	-- du §10.7.7, « 40/40 », chaque état d'une carte du Conseillé
	-- -----------------------------------------------------------------------------------------
	local ZERO =
		{ snack = 0, star = 0, decor = 0, pens = 0, cozyBed = false, gloves = 0, school = 0, monuments = 0 }
	local ALL_MAX = {
		snack = 12,
		star = 8,
		decor = 18,
		pens = 14,
		cozyBed = true,
		gloves = 40,
		school = 20,
		monuments = 10,
	}
	-- r = 0 tout neuf : Conseillé d'un joueur qui arrive (rien acheté, 40 pièces, aucun Confetti)
	add("ref.new", {
		tab = "suggested",
		select = 1,
		edit = function(p)
			tiles(p, ZERO)
			p.R = 0
			p.bestR = 0
			p.coins = 40
			p.confetti = 0
		end,
	})
	-- r = 5 (aucune Ascension) : Conseillé, puis l'onglet Ranch
	local R5_TILES = { snack = 6, star = 0, decor = 5, pens = 7, cozyBed = true, gloves = 4, school = 0 }
	local function r5(p)
		tiles(p, R5_TILES)
		p.tiles.monuments = 0
		p.R = 5
		p.bestR = 5
		p.coins = 1500000
		p.confetti = 32
	end
	add("ref.r5", { tab = "suggested", select = 1, edit = r5 })
	add("ref.r5.ranch", { tab = "ranch", select = "snack", edit = r5 })
	-- r = 20 tout au maximum (après une Ascension, Record R 24 : Monuments 10/10, Gants 40/40)
	add("ref.r20.max", {
		tab = "ranch",
		select = "gloves",
		edit = function(p)
			tiles(p, ALL_MAX)
			p.ascend = 1
			p.R = 20
			p.bestR = 24
			p.coins = 9.87e30
		end,
	})
	-- r = 10 : Tapis 20/20 (12 + 8 du Tapis Étoilé, plafond de la boucle 10)
	add("ref.r10.mat", {
		tab = "ranch",
		select = "snack",
		edit = function(p)
			tiles(p, {
				snack = 12,
				star = 8,
				decor = 14,
				pens = 14,
				cozyBed = true,
				gloves = 22,
				school = 9,
				monuments = 2,
			})
			p.R = 10
			p.bestR = 10
			p.coins = 8.5e12
		end,
	})
	-- Confettis à 99 999 (le plus large entier brut) et à 100 000 (« 100 K ») dans l'en-tête
	add("ref.confetti.99999", {
		tab = "workshop",
		select = "gift",
		edit = function(p)
			p.confetti = 99999
		end,
	})
	add("ref.confetti.100000", {
		tab = "workshop",
		select = "gift",
		edit = function(p)
			p.confetti = 100000
		end,
	})
	-- mode ×1 sur une ligne payable (les modes ×10 et Max : ranch.x10, ranch.max.preview)
	add("ref.mode.x1", {
		tab = "ranch",
		select = "gloves",
		edit = function(p)
			tiles(p, { gloves = 5 })
			p.coins = 9.99e30
		end,
	})
	-- Atelier vide, à moitié, complet (toutes les lignes ouvertes : Record R 12, une Ascension) ;
	-- complet : sélection dans « Pour le plaisir », titre de section visible
	local function atelier(levels)
		return function(p)
			p.ascend = 1
			p.R = 12
			p.bestR = 12
			p.atelier = levels
			p.confetti = 139
		end
	end
	add(
		"ref.atelier.empty",
		{ tab = "workshop", select = "gift", edit = atelier({ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }) }
	)
	add("ref.atelier.half", {
		tab = "workshop",
		select = "keptDecor",
		edit = atelier({ 1, 2, 1, 1, 1, 2, 1, 0, 1, 0 }),
	})
	add("ref.atelier.full", {
		tab = "workshop",
		select = "fun.palettes",
		edit = atelier({ 2, 3, 3, 2, 2, 3, 2, 1, 3, 0 }),
	})
	-- Souvenir de gelée actif : remontée à r = 4 après une Ascension (Record R 15 : « Souvenir ×3 »)
	add("ref.souvenir", {
		tab = "ranch",
		select = "snack",
		edit = function(p)
			tiles(p, {
				snack = 4,
				star = 0,
				decor = 6,
				pens = 14,
				cozyBed = true,
				gloves = 12,
				school = 6,
				monuments = 2,
			})
			p.ascend = 1
			p.R = 4
			p.bestR = 15
			p.coins = 3200000
		end,
	})
	-- Pires libellés du §10.7.7 en français : bandeau du Tapis Étoilé au plafond de la boucle 7
	-- (« … à partir du Grand Splorch 8 dans cette boucle ») et de la boucle 9 (« … 10 … », deux chiffres)
	local function starCapped(r, star)
		return function(p)
			tiles(p, { snack = 12, star = star })
			p.ascend = 1
			p.R = r
			p.bestR = 15
			p.coins = 9.99e30
		end
	end
	add("worst.starBanner", { tab = "ranch", select = "snack", edit = starCapped(7, 2) })
	add("worst.starBanner10", { tab = "ranch", select = "snack", edit = starCapped(9, 4) })
	-- Cartes du Conseillé dans chaque état atteignable à l'écran (les 7 états de chaque gabarit :
	-- UpgradeCard.spec) : Il manque (rien de payable), En cours, Réessaie, MAX après le dernier niveau
	-- (Lit douillet), plafond de la boucle après le Tapis 12 à r = 5 (« Boucle 6 »)
	local function lastLevels(coins)
		return function(p)
			tiles(
				p,
				{ snack = 11, star = 0, decor = 18, pens = 14, cozyBed = false, gloves = 39, school = 20 }
			)
			p.R = 5
			p.bestR = 5
			p.coins = coins
		end
	end
	add("card.need", { tab = "suggested", select = 1, edit = lastLevels(10) })
	add("card.busy", { tab = "suggested", select = 1, edit = lastLevels(9.99e30), hold = 0.7 })
	add("card.retry", { tab = "suggested", select = 1, edit = lastLevels(9.99e30), hold = 0.7, after = 3.2 })
	add("card.max", {
		tab = "suggested",
		select = "card:cozyBed",
		edit = lastLevels(9.99e30),
		hold = 0.7,
		settle = 2,
		answer = upgradeAnswer({
			levels = 1,
			edit = function(p)
				lastLevels(9.99e30)(p)
				tiles(p, { cozyBed = true })
			end,
		}),
	})
	add("card.loopCap", {
		tab = "suggested",
		select = "card:snack",
		edit = lastLevels(9.99e30),
		hold = 0.7,
		settle = 2,
		answer = upgradeAnswer({
			levels = 1,
			edit = function(p)
				lastLevels(9.99e30)(p)
				tiles(p, { snack = 12 })
			end,
		}),
	})
	return list
end

-- Les 24 états clés du GDD §10.8 (captures de référence, D23) : numéro, nom du fichier de référence
-- (tests/fixtures/upgrades-reference/<nom>.<langue>.txt), écran du groupe et partie de l'interface
-- relevée (hud = toute l'interface visible : HUD et rail ; sinon la fenêtre de l'écran Améliorations)
Screens.REFERENCE = {
	{ n = 1, name = "01-r0-neuf", group = "upgrades", id = "upgrades.ref.new" },
	{ n = 2, name = "02-r5-conseille", group = "upgrades", id = "upgrades.ref.r5" },
	{ n = 3, name = "03-r5-ranch", group = "upgrades", id = "upgrades.ref.r5.ranch" },
	{ n = 4, name = "04-r20-tout-max", group = "upgrades", id = "upgrades.ref.r20.max" },
	{ n = 5, name = "05-r3-boucle6", group = "upgrades", id = "upgrades.ranch.loop" },
	{ n = 6, name = "06-r10-tapis-20", group = "upgrades", id = "upgrades.ref.r10.mat" },
	{ n = 7, name = "07-pieces-1e300", group = "upgrades", id = "upgrades.ranch.huge" },
	{ n = 8, name = "08-confettis-99999", group = "upgrades", id = "upgrades.ref.confetti.99999" },
	{ n = 9, name = "09-confettis-100000", group = "upgrades", id = "upgrades.ref.confetti.100000" },
	{ n = 10, name = "10-tout-verrouille", group = "upgrades", id = "upgrades.workshop.empty" },
	{ n = 11, name = "11-en-cours", group = "upgrades", id = "upgrades.buy.busy" },
	{ n = 12, name = "12-reessaie", group = "upgrades", id = "upgrades.buy.retry" },
	{ n = 13, name = "13-mode-x1", group = "upgrades", id = "upgrades.ref.mode.x1" },
	{ n = 14, name = "14-mode-x10", group = "upgrades", id = "upgrades.ranch.x10" },
	{ n = 15, name = "15-mode-max", group = "upgrades", id = "upgrades.ranch.max.preview" },
	{ n = 16, name = "16-atelier-vide", group = "upgrades", id = "upgrades.ref.atelier.empty" },
	{ n = 17, name = "17-atelier-moitie", group = "upgrades", id = "upgrades.ref.atelier.half" },
	{ n = 18, name = "18-atelier-complet", group = "upgrades", id = "upgrades.ref.atelier.full" },
	{ n = 19, name = "19-souvenir", group = "upgrades", id = "upgrades.ref.souvenir" },
	{ n = 20, name = "20-carte-jelly-ascend", group = "upgrades", id = "upgrades.suggested.ascend" },
	{ n = 21, name = "21-plopettes-sieste", group = "upgrades", id = "upgrades.helpers" },
	{ n = 22, name = "22-hud-calme-pret", group = "hudv2", id = "hudv2.ready", hud = true },
	{ n = 23, name = "23-rail-jelly-ascend", group = "hudv2", id = "hudv2.railAscend", hud = true },
	{ n = 24, name = "24-hud-remontee", group = "hudv2", id = "hudv2.petitChip", hud = true },
}

-- v2.0 (lot B3) : écrans de renaissance et de méta, remplis étape par étape (plan B3, D26). Étape 1 :
-- la bannière de la Jelly Ascend (« banner.ascend », renommée de « ascend.banner », D18) avec un nom de
-- 20 caractères (Screens.LONG_NAME) ; les pires cas des étapes suivantes s'ajoutent ici.
-- Étape 2 : aperçus de renaissance (Panels/SplorchPreview, chemin v2.0) : instantané du serveur
-- fabriqué (profil témoin v2 : r, Record R, A), profil répliqué v2, EventState.features.v2 (les 11
-- interrupteurs ouverts DANS le scénario), attribut AscendReady de MON ranch ; pires cas : 1,00e300
-- pièces, nom d'espèce le plus long, Record R 21 / 22 / 30, A = 0 … 9 puis la constellation, file,
-- carte « Prêt à monter ? »
local META_V2 = {
	RecordR = true,
	JellyAscend = true,
	PetitSplorch = true,
	Confetti = true,
	Workshop = true,
	Carnet = true,
	WeeklyTrack = true,
	Mastery = true,
	RanchSkins = true,
	DecoPerso = true,
	Hearts = true,
}
local META_DONE = { step = 11, done = true, demoDone = true }

local function metaFlags(except)
	local out = {}
	for k, v in META_V2 do
		if k ~= except then
			out[k] = v
		end
	end
	return out
end

-- Aperçu de renaissance v2.0 ouvert dans l'état demandé : opts.r, opts.bestR, opts.A (instantané),
-- opts.edit(p) (profil témoin), opts.coins / opts.pot (profil répliqué), opts.loop (prestige de boucle
-- prêt, vrai par défaut), opts.ascend (AscendReady), opts.flags (features.v2), opts.spectacle,
-- opts.tab, opts.longest (envol : espèce au nom le plus long)
local function previewState(c, opts)
	closeAll(c)
	flushAll(c)
	unstub(c)
	local r = opts.r or 5
	-- dans son ranch (l'écran « hors du ranch » l'en sort)
	c.h:moveTo(c.h.localPlayer, c.WorldLayout.spawnCFrame(1).Position + Vector3.new(0, 3, 0))
	Screens.myRanchModel(c, { HelperMode = "active", AscendReady = opts.ascend == true })
	local snap = Screens.upgradeSnapshot(c, function(p, UM)
		p.R = r
		p.bestR = opts.bestR or r
		p.ascend = opts.A or 0
		if opts.edit then
			opts.edit(p, UM)
		end
	end)
	local function squishy(s, z, bf)
		return { s = s, m = 0, st = 0, z = z, zg = 0, at = "pen", bf = bf, o = "", lk = false, b = 0, gd = 0 }
	end
	local loop = opts.loop ~= false
	c.h:fireClient(REMOTES .. "DataPatch", {
		onboarding = META_DONE,
		version = 2,
		R = r,
		coins = opts.coins or 1234567,
		pot = opts.pot or 0,
		growth = { G = 0, g = 0, t = c.Clock.now() },
		squishies = {
			v2a = squishy(1, if loop then 1e100 else 10, 1),
			v2b = squishy(if opts.longest then longestSpecies(c) else 5, if loop then 5e99 else 5, 0),
		},
	}, {})
	c.h:fireClient(REMOTES .. "DataPatch", { upgradeSnapshot = snap }, {})
	frames(c, 3, 0.1)
	ranchStub(c, "cozy")
	local features = table.clone(FEATURES)
	features.v2 = opts.flags or META_V2
	local ev = eventStub(c, c.Clock.now(), { features = features })
	c.WSC.EventChanged:Fire(ev)
	frames(c, 2, 0.1)
	open(c, "SplorchPreview", opts.tab)
	-- MON prestige arrivé dans la file écran ouvert (l'entrée du rail n'ouvre rien pendant MON prestige)
	if opts.spectacle then
		unstub(c)
		c.WSC.EventChanged:Fire(
			eventStub(c, c.Clock.now(), { features = features, spectacle = opts.spectacle })
		)
		frames(c, 3, 0.1)
	end
end

local function metaScreens()
	local list = {}
	table.insert(list, {
		id = "meta.banner.ascend",
		run = function(c)
			closeAll(c)
			flushAll(c)
			c.Banners.show({
				kind = "ascend",
				args = { name = Screens.LONG_NAME, userId = c.players[1].UserId },
				priority = 1,
			})
			frames(c, 4, 0.1)
		end,
	})
	local function add(id, run)
		table.insert(list, { id = "meta.preview." .. id, run = run })
	end
	local function payable(coins)
		return function(p)
			p.coins = coins
			p.tiles.pens = 3
		end
	end
	-- Grand Splorch : nouveau record R5 → 6 (phrase neutre : rien de gardé n'est payable)
	add("grand.new", function(c)
		previewState(c, { r = 5 })
	end)
	-- ligne rouge et « Dépenser d'abord » (Enclos payable)
	add("grand.spend", function(c)
		previewState(c, { r = 5, edit = payable(1e30) })
	end)
	-- pire nombre : 1,00e300 pièces perdues
	add("grand.huge", function(c)
		previewState(c, { r = 5, coins = 1e300, edit = payable(1e300) })
	end)
	-- beaucoup de pièces mais aucune ligne gardée payable : la phrase neutre
	add("grand.neutral", function(c)
		previewState(c, { r = 8, coins = 9.99e35 })
	end)
	-- record regagné (Petit Splorch coupé) : « Cadeau du Splorch »
	add("grand.regained", function(c)
		previewState(c, { r = 5, bestR = 10, A = 1, flags = metaFlags("PetitSplorch") })
	end)
	-- refus (hors du ranch) à côté de « Dépenser d'abord »
	add("grand.away", function(c)
		previewState(c, { r = 5, edit = payable(1e30) })
		c.h:moveTo(c.h.localPlayer, Vector3.new(0, 3, 0))
		frames(c, 4, 0.1)
	end)
	-- plus gros squishy redevenu trop petit écran ouvert : « Plus gros : … / … »
	add("grand.notready", function(c)
		previewState(c, { r = 5 })
		c.h:fireClient(REMOTES .. "DataPatch", {
			squishies = {
				v2a = {
					s = 1,
					m = 0,
					st = 0,
					z = 10,
					zg = 0,
					at = "pen",
					bf = 1,
					o = "",
					lk = false,
					b = 0,
					gd = 0,
				},
			},
		}, {})
		frames(c, 4, 0.1)
	end)
	-- Détails : deux colonnes, prochain objectif, envol au nom d'espèce le plus long, « Filmer »
	add("grand.details", function(c)
		previewState(c, { r = 5, longest = true })
		local SP = c.h:require(CLIENT .. "UI.Panels.SplorchPreview")
		local parts = SP._v2()
		activate(c, parts.details)
		-- la sélection sur la flèche de droite (cadre de focus dessiné), l'envol au nom le plus long
		c.h.game.GuiService.SelectedObject = parts.nextFlyer
		frames(c, 4, 0.1)
	end)
	-- déblocages nommés du Record R : Plopette (R4), Cuve dorée (R7), déco gardée (R8), Tapis Étoilé
	-- (R9), prime de record (R21), Monument (R22), titre (R30)
	for _, r in { 3, 6, 7, 8, 20, 21, 29 } do
		add("grand.r" .. (r + 1), function(c)
			previewState(c, { r = r })
		end)
	end
	-- premier Petit Splorch de la remontée
	add("petit.first", function(c)
		previewState(c, { r = 4, bestR = 12, A = 1 })
	end)
	-- boucle ET Jelly Ascend prêtes : barre d'onglets « Grand Splorch » / « Jelly Ascend »
	add("tabs", function(c)
		previewState(c, { r = 15, A = 0, ascend = true })
	end)
	-- Jelly Ascend de A0 à A9 (condition juste atteinte) : ciel de l'Ascension suivante, départ
	local Prestige = nil
	for A = 0, 9 do
		add("ascend.a" .. A, function(c)
			Prestige = Prestige or c.h:require("ReplicatedStorage.Shared.Logic.Prestige")
			local need = Prestige.reqR(A + 1)
			previewState(c, { r = need, A = A, ascend = true, loop = false, tab = "ascend" })
		end)
	end
	-- au-delà de A10 : la constellation et ses étoiles
	add("ascend.stars", function(c)
		Prestige = Prestige or c.h:require("ReplicatedStorage.Shared.Logic.Prestige")
		previewState(c, { r = Prestige.reqR(16), A = 15, ascend = true, loop = false, tab = "ascend" })
	end)
	-- MON Grand Splorch dans la file : « Ton Grand Splorch passe d'abord ! », maintien refusé
	add("ascend.queued", function(c)
		previewState(c, {
			r = 15,
			A = 0,
			ascend = true,
			loop = false,
			tab = "ascend",
			spectacle = {
				queue = {
					{
						kind = "splorch",
						userId = c.h.localPlayer.UserId,
						startAt = c.Clock.now() + 20,
						slot = 1,
						position = 1,
						eta = 20,
					},
				},
			},
		})
	end)
	-- carte « Prêt à monter ? » après le maintien de 3 s (✕ relâché, garde passée : boutons actifs)
	add("ascend.card", function(c)
		previewState(c, { r = 15, A = 0, ascend = true, loop = false, tab = "ascend" })
		local SP = c.h:require(CLIENT .. "UI.Panels.SplorchPreview")
		c.h.game.GuiService.SelectedObject = SP._v2().ascendHold
		c.h:settle(1)
		frames(c, 5, 0.1)
		Gamepad.press(c.h, Enum.KeyCode.ButtonA)
		frames(c, 100, 1 / 30)
		Gamepad.release(c.h, Enum.KeyCode.ButtonA)
		frames(c, 10, 0.1)
	end)
	-- Étape 3 : Panels/Ranch › Mon style (D10, D11) : profil v2 répliqué (Record R 30, A = 3, palettes
	-- de l'Atelier Bonbon / Menthe / Lavande, selle Biscuit de la piste, 600 niveaux, géant 2e15, Fanion,
	-- Gamelle), attribut DecoPerso de MON ranch, instantané (Dalles retirées), EventState.features.v2 ;
	-- pires cas : noms français les plus longs sur le plan, 66 titres (début, fin, « taille 1e24 »),
	-- sources verrouillées (Carnet 10 000, taille 1e15 / 1e24, saison, semaine, Atelier, Ascension)
	local function styleState(c, opts)
		closeAll(c)
		flushAll(c)
		unstub(c)
		c.h:moveTo(c.h.localPlayer, c.WorldLayout.spawnCFrame(1).Position + Vector3.new(0, 3, 0))
		Screens.myRanchModel(c, { DecoPerso = opts.deco or "1,7,0,0,0,0,0,0,0,0,0,0" })
		local snap = Screens.upgradeSnapshot(c, function(p)
			p.R = 30
			p.bestR = 30
			p.ascend = 3
		end)
		local poor = opts.poor == true
		local profile = {
			onboarding = META_DONE,
			version = 2,
			R = 30,
			bestR = 30,
			ascend = 3,
			plopDays = if poor then 0 else 8,
			cosmetics = {
				saddle = "classic",
				trail = "",
				title = "",
				theme = "marshmallow",
				flag = "",
				palette = "candy",
				cushions = "",
			},
			outfits = { owned = { plopBib = 1, partyHat = 1 }, worn = {} },
			atelierCosmetics = { if poor then 0 else 7 },
			stats = if poor
				then { upgradesBought = 0, playSeconds = 0, objectivesClaimed = 0, tracksDone = 0 }
				else { upgradesBought = 600, playSeconds = 400, objectivesClaimed = 30, tracksDone = 1 },
			weeklyTrack = { won = { if poor then 0 else 1 } },
			biggestEver = if poor then 10 else 2e15,
			season = { frostDays = 0 },
			moon = { sessions = if poor then 0 else 1 },
			decoPerso = { owned = { 0, 0 }, slots = { 1, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } },
		}
		c.h:fireClient(REMOTES .. "DataPatch", profile, {})
		c.h:fireClient(REMOTES .. "DataPatch", { upgradeSnapshot = snap }, {})
		frames(c, 3, 0.1)
		ranchStub(c, "cozy")
		local features = table.clone(FEATURES)
		features.v2 = opts.flags or META_V2
		local ev = eventStub(c, c.Clock.now(), { features = features })
		c.WSC.EventChanged:Fire(ev)
		frames(c, 2, 0.1)
		open(c, "Ranch", "style")
		local Ranch = c.h:require(CLIENT .. "UI.Panels.Ranch")
		if opts.kind then
			local b = Ranch._styleKindButton(opts.kind)
			if b then
				activate(c, b)
			end
		end
		if opts.slot then
			local b = Ranch._decoSlot(opts.slot)
			if b then
				activate(c, b)
			end
		end
		-- case à montrer (la liste virtualisée défile jusqu'à elle) : « last » = la dernière
		if opts.show then
			local entries = Ranch._styleEntries()
			local want = if opts.show == "last" then entries[#entries] else nil
			if want == nil then
				for _, e in entries do
					if e.id == opts.show then
						want = e
					end
				end
			end
			local cell = if want then Ranch._styleCell(want.kind, want.id) else nil
			if cell then
				c.h.game.GuiService.SelectedObject = cell
				c.h:settle(1)
				frames(c, 6, 0.1)
			end
		end
	end
	local function style(id, opts)
		table.insert(list, {
			id = "meta.style." .. id,
			run = function(c)
				styleState(c, opts)
			end,
		})
	end
	style("theme", {}) -- 14 habillages, l'habillage équipé sélectionné
	style("saddle", { kind = "saddle" })
	style("saddle.last", { kind = "saddle", show = "last" })
	style("trail", { kind = "trail", show = "last" })
	style("titles.first", { kind = "title" })
	style("titles.size", { kind = "title", show = "sunKeeper", poor = true })
	style("titles.last", { kind = "title", show = "last" })
	style("flag", { kind = "flag" })
	style("outfits", { kind = "outfits" })
	style("palette", { kind = "palette" })
	style("cushions", { kind = "cushions" })
	style("locked", { kind = "saddle", show = "last", poor = true })
	-- Déco perso : plan vide, plan plein (noms français les plus longs : petits 1-8, grands 9-12)
	style("deco.empty", { kind = "deco", deco = "0,0,0,0,0,0,0,0,0,0,0,0" })
	style("deco.full", { kind = "deco", deco = "17,4,21,31,5,34,26,1,37,12,25,27" })
	style("deco.pickerP", { kind = "deco", deco = "0,0,0,0,0,0,0,0,0,0,0,0", slot = 2 })
	style(
		"deco.pickerP.last",
		{ kind = "deco", deco = "0,0,0,0,0,0,0,0,0,0,0,0", slot = 2, show = "last", poor = true }
	)
	style("deco.pickerG", { kind = "deco", deco = "0,0,0,0,0,0,0,0,0,0,0,0", slot = 9, poor = true })
	style("deco.pickerG.last", { kind = "deco", deco = "0,0,0,0,0,0,0,0,0,0,0,0", slot = 9, show = "last" })

	-- Étape 4 : Objectifs (« Cette semaine », Défis, Carnet), Squishydex (Records, maîtrise), Réglages
	-- (halo, emotes gagnées) ; profil v2 répliqué, EventState.features.v2 ; à T0 (vendredi, semaine 2975)
	-- le cosmétique de la semaine est le 8e de la rotation, Coussins « Nuage rose » (le plus long en
	-- français) ; Défis aux noms les plus longs (« Fais naître 2 Rares ou mieux »)
	local WEEK, EPOCH = 604800, 345600
	local function v2Event(c, flags)
		ranchStub(c, "cozy")
		local features = table.clone(FEATURES)
		features.v2 = flags or META_V2
		c.WSC.EventChanged:Fire(eventStub(c, c.Clock.now(), { features = features }))
		frames(c, 2, 0.1)
	end
	local PARTIAL = {
		{ id = 7, p = 1, done = false },
		{ id = 6, p = 1, done = true },
		{ id = 12, p = 17, done = false },
	}
	local function goalsState(c, opts)
		closeAll(c)
		flushAll(c)
		unstub(c)
		local week = math.floor((c.Clock.unix() - EPOCH) / WEEK)
		c.h:fireClient(REMOTES .. "DataPatch", {
			onboarding = META_DONE,
			version = 2,
			objectives = opts.objectives,
			weeklyTrack = {
				period = if opts.first then 0 else week,
				firstPeriodEnd = if opts.first then 0 else EPOCH + (week - 4) * WEEK,
				points = opts.points or 9,
				claimed = { opts.claimed or 15 },
				won = { opts.won or 0 },
				challenges = opts.challenges or PARTIAL,
				play = { 0, 0, 0, 0, 0, 0, 0 },
				playDay = 0,
			},
			carnet = { opts.carnet or 15 },
			stats = {
				upgradesBought = opts.bought or 600,
				playSeconds = 400,
				objectivesClaimed = 30,
				tracksDone = 1,
				splorches = 40,
				bestCombo = 12,
			},
		}, {})
		frames(c, 3, 0.1)
		v2Event(c, opts.flags)
		open(c, "Objectives", opts.tab or "track")
	end
	local function goals(id, opts)
		table.insert(list, {
			id = "meta.goals." .. id,
			run = function(c)
				goalsState(c, opts)
			end,
		})
	end
	goals("track.first", { first = true, points = 0, claimed = 0, challenges = {} }) -- 1re période : 10 jours
	goals("track.full", { points = 30, claimed = 4095 }) -- 24 / 24, les 12 paliers réclamés
	goals("track.cosmetic.next", {}) -- rien de gagné : la semaine prochaine, dans 2 semaines
	goals("track.cosmetic.six", { won = 31 + 128 }) -- celui de la période et les 5 suivants gagnés
	goals("challenges", {
		challenges = {
			{ id = 7, p = 2, done = true },
			{ id = 10, p = 3, done = true },
			{ id = 9, p = 2, done = true },
		},
	})
	goals("carnet.0", { tab = "carnet", bought = 0, carnet = 0 })
	goals("carnet.2500", { tab = "carnet", bought = 2500, carnet = 63 })
	goals("carnet.10000", { tab = "carnet", bought = 10000, carnet = 255 })
	-- v1.3 dans le même panneau : relance du jour déjà utilisée (« Plus de relance aujourd'hui »)
	goals("today.noReroll", {
		tab = "today",
		objectives = {
			day = math.floor(T0 / 86400),
			list = {
				{ id = 1, p = 3, done = false, claimed = false },
				{ id = 7, p = 0, done = false, claimed = false },
				{ id = 14, p = 0, done = false, claimed = false },
			},
			rerolls = 1,
			allClaimed = false,
		},
	})

	-- Squishydex : Livre des records (plus gros squishy 1e300, compteurs à 5 chiffres) et maîtrise
	-- (Plop maîtrisé 3 / 3 ; 2e espèce 0 / 3 avec un trophée d'or ; 3e 1 / 3 avec un trophée d'argent)
	local function dexState(c, opts)
		closeAll(c)
		flushAll(c)
		unstub(c)
		local mut = table.create(26, 0)
		local stars = table.create(26, 0)
		mut[1], mut[2], mut[3] = 1023, 1, 1
		stars[1], stars[3] = 31, 16
		c.h:fireClient(REMOTES .. "DataPatch", {
			onboarding = META_DONE,
			version = 2,
			R = 30,
			bestR = 30,
			ascend = 3,
			biggestEver = if opts.empty then 0 else 1e300,
			confettiTotal = if opts.empty then 0 else 99999,
			stats = if opts.empty then {} else { bestCombo = 99, splorches = 99999, upgradesBought = 999999 },
			mastery = { 2 },
			plopDays = if opts.empty then 0 else 9999,
			hearts = { receivedTotal = if opts.empty then 0 else 99999, givenDay = 0, givenTo = {} },
			dex = { mut = mut, stars = stars, fam = table.create(7, 0), rewards = 0 },
			trophies = { 2e12, 2e9, 5e6 },
		}, {})
		frames(c, 3, 0.1)
		v2Event(c, opts.flags)
		open(c, "Squishydex", opts.tab or "species")
		if opts.species then
			local row = c.PC.window("Squishydex").Body.Page_species.Species.Holder:FindFirstChild("Row1")
			local cell = row and row:FindFirstChild("Cell" .. opts.species)
			if cell then
				activate(c, cell)
			end
		end
	end
	local function dexScreen(id, opts)
		table.insert(list, {
			id = "meta.dex." .. id,
			run = function(c)
				dexState(c, opts)
			end,
		})
	end
	dexScreen("records", { tab = "records" })
	dexScreen("records.empty", { tab = "records", empty = true })
	dexScreen("mastery.3", { species = 1 })
	dexScreen("mastery.0", { species = 2 })
	dexScreen("mastery.1", { species = 3 })

	-- Réglages : « Montrer mon halo » (attribut HaloOn de MON ranch) et emote de la croix ← (nom le plus
	-- long des emotes gagnées : « Couronne de confettis », Record R 19 ; Belly Flop au 10e jour de Plop,
	-- Couronne au jalon 260 du Squishydex)
	local function settingsState(c, opts)
		closeAll(c)
		flushAll(c)
		unstub(c)
		Screens.myRanchModel(c, { HaloOn = true })
		local settings = table.clone(c.data.settings or {})
		settings.lang = c.lang
		settings.emoteLeft = opts.emote or "bravo"
		settings.haloOn = opts.halo ~= false
		local dex = table.clone(c.data.dex or {})
		dex.rewards = if opts.emote == "crown" then 260 else 0
		c.h:fireClient(REMOTES .. "DataPatch", {
			onboarding = META_DONE,
			version = 2,
			R = 30,
			bestR = 30,
			ascend = 3,
			plopDays = if opts.emote == "bellyFlop" then 10 else 8,
			dex = dex,
			stats = { upgradesBought = 2500, playSeconds = 400, objectivesClaimed = 30, tracksDone = 1 },
			weeklyTrack = { won = { 16 } },
			settings = settings,
		}, {})
		frames(c, 3, 0.1)
		v2Event(c, opts.flags)
		open(c, "Settings")
		local Settings = c.h:require(CLIENT .. "UI.Panels.Settings")
		local control = Settings._controlFor(opts.show or "haloOn")
		if control then
			c.h.game.GuiService.SelectedObject = control
			c.h:settle(1)
			frames(c, 6, 0.1)
		end
	end
	local function settingsScreen(id, opts)
		table.insert(list, {
			id = "meta.settings." .. id,
			run = function(c)
				settingsState(c, opts)
			end,
		})
	end
	settingsScreen("halo", {})
	settingsScreen("halo.off", { halo = false })
	settingsScreen("emotes", { emote = "confettiCrown", show = "emoteLeft" })
	settingsScreen("emote.bellyFlop", { emote = "bellyFlop", show = "emoteLeft" })
	settingsScreen("emote.crown", { emote = "crown", show = "emoteLeft" })

	-- Lot B3, étape 5 (D19-D22) : cartes de la v2.0 (noms les plus longs de la langue), petite ligne du
	-- Grand Splorch, Pluie d'étoiles, écran de retour du Petit Splorch, jumelles et leur invite
	local Cos = nil
	local function cosmetics(c)
		Cos = Cos or c.h:require("ReplicatedStorage.Shared.Config.Cosmetics")
		return Cos
	end
	-- clé de la liste dont la traduction est la plus longue dans la langue du client
	local function longestKey(c, keys)
		local best, bestLen = keys[1], -1
		for _, key in keys do
			local text = c.Prefs.t(key)
			local n = utf8.len(text) or #text
			if n > bestLen then
				best, bestLen = key, n
			end
		end
		return best
	end
	-- « kind.id » de Cosmetics.ListV2 / WeeklyRotation (filtre facultatif) au nom le plus long
	local function longestV2(c, filter)
		local C = cosmetics(c)
		local keys, refs = {}, {}
		for _, list2 in { C.ListV2, C.WeeklyRotation } do
			for _, def in list2 do
				if filter == nil or filter(def) then
					table.insert(keys, def.key)
					refs[def.key] = def
				end
			end
		end
		return refs[longestKey(c, keys)]
	end
	local function v2State(c, opts)
		closeAll(c)
		flushAll(c)
		unstub(c)
		-- cartes rangées des écrans précédents oubliées : la carte rouverte est celle de cet écran
		for _, card in c.Cards.pending() do
			c.Cards.dismiss(card.id)
		end
		local snap = Screens.upgradeSnapshot(c, function(p)
			p.R = opts.r or 30
			p.bestR = opts.bestR or 30
			p.ascend = opts.A or 3
		end)
		c.h:fireClient(
			REMOTES .. "DataPatch",
			{ onboarding = META_DONE, version = 2, upgradeSnapshot = snap },
			{}
		)
		frames(c, 3, 0.1)
		v2Event(c, opts.flags)
	end
	-- carte affichée (8 s à droite) ; opts.reopen : rangée puis rouverte depuis « ! »
	local function cardScreen(id, kind, data, opts)
		opts = opts or {}
		table.insert(list, {
			id = "meta.card." .. id,
			run = function(c)
				v2State(c, opts)
				local d = if type(data) == "function" then data(c) else data
				if kind == "element" then
					c.h:require(CLIENT .. "Controllers.RanchRenderer").ElementBuilt:Fire(c.WSC.mySlot(), d.id)
				else
					c.h:fireClient(REMOTES .. "Celebrate", { kind = kind, data = d })
				end
				frames(c, 8, 0.1)
				if opts.reopen then
					flushCards(c)
					local pending = c.Cards.pending()
					local last = pending[#pending]
					if last then
						c.Cards.open(last.id)
						frames(c, 6, 0.1)
					end
				end
			end,
		})
	end
	local HIGHLIGHTS = { highlights = { "unlock.workshop", "unlock.gloves", "unlock.skin" } }
	cardScreen("welcomeV2", "welcomeV2", HIGHLIGHTS)
	cardScreen("welcomeV2.open", "welcomeV2", HIGHLIGHTS, { reopen = true })
	cardScreen("regainDone", "regainDone", { bestR = 400, confetti = 99999 }, { r = 399, bestR = 400 })
	cardScreen("regainDone.one", "regainDone", { bestR = 15, confetti = 1 }, { reopen = true })
	cardScreen("recordStep", "recordStep", { share = 0.75 })
	cardScreen("unlock.deco", "unlock", function(c)
		local keys, ids = {}, {}
		for _, def in cosmetics(c).DecoPerso do
			table.insert(keys, def.key)
			ids[def.key] = def.id
		end
		return { kind = "deco", id = ids[longestKey(c, keys)] }
	end)
	cardScreen("unlock.v2.open", "unlock", function(c)
		local def = longestV2(c, function(d)
			return d.kind ~= "emote"
		end)
		return { kind = def.kind, id = def.id }
	end, { reopen = true })
	-- unlock2 : 2e déblocage des Records R 1 (Gants), 15 (Jelly Ascend) et 17 (habillage)
	for _, r in { 1, 15, 17 } do
		cardScreen("unlock2.r" .. r, "unlock2", { recordR = r, keys = {} })
	end
	cardScreen("trackTier.confetti", "trackTier", { tier = 11, reward = "confetti" })
	cardScreen("trackTier.drop", "trackTier", { tier = 8, reward = "drop" }, { reopen = true })
	cardScreen("trackTier.cosmetic", "trackTier", function(c)
		local C = cosmetics(c)
		local keys, refs = {}, {}
		for _, def in C.WeeklyRotation do
			table.insert(keys, def.key)
			refs[def.key] = def
		end
		local def = refs[longestKey(c, keys)]
		return { tier = 12, reward = def.kind .. "." .. def.id }
	end)
	cardScreen("carnet", "carnet", function(c)
		local Quests = c.h:require("ReplicatedStorage.Shared.Config.Quests")
		local C = cosmetics(c)
		local keyOf = {}
		for _, def in C.ListV2 do
			keyOf[def.kind .. "." .. def.id] = def.key
		end
		local keys, tierOf, refOf = {}, {}, {}
		for i, at in Quests.Carnet.Tiers do
			local ref = Quests.Carnet.Rewards[at]
			local key = ref and keyOf[ref]
			if key then
				table.insert(keys, key)
				tierOf[key], refOf[key] = i, ref
			end
		end
		local key = longestKey(c, keys)
		return { tier = tierOf[key], reward = refOf[key] }
	end)
	cardScreen("mastery", "mastery", function(c)
		return { species = longestSpecies(c) }
	end, { reopen = true })
	-- premier passage d'un élément de MON ranch : le palier, le Monument au nom le plus long, la
	-- maisonnette (les autres noms de la même famille passent dans la même case, TextFitKeys)
	cardScreen("element.tier", "element", function(c)
		local keys = {}
		for n = 1, 6 do
			table.insert(keys, "ranchTier." .. n)
		end
		local key = longestKey(c, keys)
		return { id = "tier" .. string.match(key, "%d+$") .. ".built" }
	end)
	cardScreen("element.monument", "element", function(c)
		local keys = {}
		for n = 1, 10 do
			table.insert(keys, "monument." .. n)
		end
		return { id = longestKey(c, keys) }
	end)
	cardScreen("element.monument10", "element", { id = "monument.10" })
	cardScreen("element.house", "element", { id = "helper.house" })

	-- petite ligne du Grand Splorch d'un autre (sa bannière ne vient pas : une toutes les 3 min) et
	-- Pluie d'étoiles de la Jelly Ascend d'un autre (messages du HUD)
	table.insert(list, {
		id = "meta.message.splorchLine",
		run = function(c)
			v2State(c, {})
			local now = c.Clock.now()
			c.h:fireClient(REMOTES .. "Celebrate", {
				kind = "splorch",
				data = {
					userId = c.players[1].UserId,
					level = 1,
					flyer = { s = 1, m = 0, st = 0, z = 10 },
					startedAt = now,
					burstAt = now + 1,
					endsAt = now + 5,
					short = false,
				},
			})
			frames(c, 30, 0.1)
		end,
	})
	table.insert(list, {
		id = "meta.message.starRain",
		run = function(c)
			v2State(c, {})
			local now = c.Clock.now()
			local hero = c.players[1].UserId
			c.h:fireClient(REMOTES .. "Celebrate", {
				kind = "ascend",
				data = {
					userId = hero,
					ascend = 2,
					startR = 1,
					bestR = 30,
					startedAt = now,
					burstAt = now + 4,
					endsAt = now + 10,
					flyer = { s = 1, m = 0, st = 0, z = 10 },
				},
			})
			c.h:fireClient(REMOTES .. "Celebrate", {
				kind = "giftRain",
				data = {
					heroId = hero,
					heroName = Screens.LONG_NAME_2,
					coins = 0,
					uid = "",
					species = 0,
					short = false,
				},
			})
			frames(c, 4, 0.1)
		end,
	})
	-- écran de retour pendant une remontée (Petit Splorch prêt / presque prêt)
	for _, variant in { { "petit", true, false }, { "petitNearly", false, true } } do
		table.insert(list, {
			id = "meta.return." .. variant[1],
			run = function(c)
				v2State(c, { r = 12, bestR = 30, A = 2 })
				c.h:fireClient(REMOTES .. "Celebrate", {
					kind = "return",
					data = {
						seconds = 43199,
						uid = "u1",
						species = longestSpecies(c),
						grew = 1.23456789e18,
						pot = 9.87654321e17,
						splorchReady = variant[2],
						nearlyReady = variant[3],
					},
				})
				frames(c, 30, 0.1)
			end,
		})
	end
	-- jumelles : devant le portail du ranch 2 (voisin au nom long, BestR posé), invite □ « Regarder »,
	-- puis la fenêtre du cœur (normal, déjà donné, plafond du jour)
	local function binocularsState(c, hearts)
		v2State(c, {})
		local function child(parent, name, class)
			local f = parent:FindFirstChild(name)
			if f == nil then
				f = MockInstance.new(class)
				f.Name = name
				f.Parent = parent
			end
			return f
		end
		local world = child(c.h.workspace, "Wobbleton", "Folder")
		child(child(world, "Ranches", "Folder"), "2", "Model"):SetAttribute("BestR", 12)
		if hearts then
			c.h:fireClient(REMOTES .. "DataPatch", { hearts = hearts }, {})
			c.h:settle(1)
		end
		c.h:moveTo(c.h.localPlayer, c.WorldLayout.gateOutside(2))
		frames(c, 12, 1 / 30)
		refreshHud(c)
	end
	table.insert(list, {
		id = "meta.binoculars.prompt",
		run = function(c)
			binocularsState(c, nil)
		end,
	})
	local function others(n)
		local out = {}
		for i = 1, n do
			out[i] = 9000 + i
		end
		return out
	end
	for _, variant in
		{
			{ "give", nil },
			{ "given", "given" },
			{ "limit", "limit" },
		}
	do
		table.insert(list, {
			id = "meta.binoculars." .. variant[1],
			run = function(c)
				local day = math.floor(c.Clock.now() / 86400)
				local hearts = nil
				if variant[2] == "given" then
					hearts = { receivedTotal = 0, givenDay = day, givenTo = { c.players[1].UserId } }
				elseif variant[2] == "limit" then
					hearts = { receivedTotal = 0, givenDay = day, givenTo = others(20) }
				end
				binocularsState(c, hearts)
				c.Clock.advance(1)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonX)
				c.h:settle(2)
				frames(c, 12, 1 / 30)
			end,
		})
	end
	return list
end

-- Groupes d'écrans : un client démarré par groupe (état de données), écrans joués dans l'ordre
-- ---------------------------------------------------------------------------------------------
-- v2.0 (lot B5) : la vie des squishies. Étape 2 : l'annonce d'un tour appris (message du HUD, clé
-- trick.new) avec le nom de tour le plus long de la langue ; l'interrupteur Personalities est ouvert
-- DANS le scénario (EventState.features.v2), jamais dans le jeu livré
-- ---------------------------------------------------------------------------------------------
local function lifeScreens()
	local list = {}
	table.insert(list, {
		id = "life.toast.trick",
		run = function(c)
			closeAll(c)
			flushAll(c)
			unstub(c)
			local features = table.clone(FEATURES)
			features.v2 = { Personalities = true }
			c.WSC.EventChanged:Fire(eventStub(c, c.Clock.now(), { features = features }))
			frames(c, 2, 0.1)
			-- tour au nom le plus long de la langue (« Feu d'artifice », « Fireworks »)
			local tricks = c.h:require("ReplicatedStorage.Shared.Config.Quests").Mastery.Tricks
			local best, bestLen = 1, -1
			for i, trick in tricks do
				local len = utf8.len(c.Prefs.t(trick.key)) or 0
				if len > bestLen then
					best, bestLen = i, len
				end
			end
			-- les records repartent de 0 (rien n'est annoncé), puis celui de Plop passe le seuil du tour :
			-- World/Personality annonce « Nouveau tour : … ! » par le message du HUD
			local records = table.create(#c.Species.List, 0)
			c.h:fireClient(REMOTES .. "DataPatch", { trophies = records }, {})
			frames(c, 2, 0.1)
			records = table.clone(records)
			records[1] = tricks[best].size
			c.h:fireClient(REMOTES .. "DataPatch", { trophies = records }, {})
			frames(c, 6, 0.1)
		end,
	})
	-- Étape 3 : étiquette du Chantier de Big Plop sur MON ranch (« Nouveau : … », clé card.unlockNew des
	-- cartes « Nouveau » du lot B3) avec le nom d'élément le plus long de la langue (paliers, Monuments,
	-- maisonnette) ; planche `.billboards.png` (texte du monde). L'élément n'est pas dessiné dans cette
	-- scène : son repère est donné un instant à RanchRenderer.elementCFrame (devant mon personnage), lu
	-- une seule fois par Big Plop quand ElementBuilt part
	table.insert(list, {
		id = "life.chantier",
		run = function(c)
			closeAll(c)
			flushAll(c)
			unstub(c)
			local ids = { "helper.house" }
			for k = 1, 6 do
				table.insert(ids, "tier" .. k .. ".x")
			end
			for k = 1, 10 do
				table.insert(ids, "monument." .. k)
			end
			local function keyOf(id)
				local tier = string.match(id, "^tier(%d)")
				return if tier then "ranchTier." .. tier else id
			end
			local best, bestLen = ids[1], -1
			for _, id in ids do
				local len = utf8.len(c.Prefs.t(keyOf(id))) or 0
				if len > bestLen then
					best, bestLen = id, len
				end
			end
			local RR = c.h:require(CLIENT .. "Controllers.RanchRenderer")
			local slot = c.WSC.mySlot()
			local WL = c.h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
			local saved = RR.elementCFrame
			RR.elementCFrame = function()
				return CFrame.new(WL.penSlot(slot, 1))
			end
			RR.ElementBuilt:Fire(slot, best)
			c.h:settle(1)
			RR.elementCFrame = saved
			frames(c, 10, 0.1)
		end,
	})
	-- Étape 4 : textes des spectacles. Tampon « JELLY ASCEND ★A » (clé ascend.stamp, étoile dessinée
	-- par UI/Text ; A = 999, le plus grand que ShowsV2 écrit) puis « ×3 à chaque boucle ! » (ascend.show),
	-- comme VFXController.stamp les pose à l'éclat ; petit texte du Petit Splorch au propriétaire
	-- (splorch.show, nom d'espèce le plus long de la langue, 32 px par UI/WorldText : planche
	-- `.billboards.png`)
	for _, entry in { { "ascend.stamp", { n = 999 } }, { "ascend.show" } } do
		table.insert(list, {
			id = "life." .. entry[1],
			run = function(c)
				closeAll(c)
				flushAll(c)
				local VFX = c.h:require(CLIENT .. "Controllers.VFXController")
				VFX.stamp(entry[1], entry[2], Color3.fromRGB(255, 205, 60))
				frames(c, 3, 0.05)
			end,
		})
	end
	table.insert(list, {
		id = "life.petit.text",
		run = function(c)
			closeAll(c)
			flushAll(c)
			frames(c, 6, 0.5)
			local VFX = c.h:require(CLIENT .. "Controllers.VFXController")
			local name = c.Prefs.t("species." .. c.Species.ById[longestSpecies(c)].key)
			local pos = c.WorldLayout.spawnCFrame(1).Position + Vector3.new(0, 6, 0)
			VFX.floatText(pos, c.Prefs.t("splorch.show", { name = name }), Color3.fromRGB(255, 205, 60), 0.8)
			frames(c, 2, 0.05)
		end,
	})
	return list
end

function Screens.groups()
	local groups = {}

	table.insert(groups, {
		id = "loading",
		loading = true,
		screens = {
			{ id = "loading.wake", failed = false },
			{ id = "loading.retry", failed = true },
		},
	})

	-- Nouveau joueur
	local new = {
		hudScreen("hud.new"),
	}
	for _, s in onboardingScreens() do
		table.insert(new, s)
	end
	table.insert(new, {
		id = "panel.Objectives.onboarding.new",
		run = function(c)
			open(c, "Objectives", "onboarding")
		end,
	})
	table.insert(new, {
		id = "panel.Ranch.pens.new",
		run = function(c)
			open(c, "Ranch", "pens")
		end,
	})
	table.insert(new, {
		id = "panel.Ranch.pads.new",
		run = function(c)
			open(c, "Ranch", "pads")
		end,
	})
	table.insert(new, {
		id = "panel.OutfitPreview.new",
		run = function(c)
			open(c, "OutfitPreview", "sweater")
		end,
	})
	table.insert(new, {
		id = "panel.SplorchPreview.notready",
		run = function(c)
			open(c, "SplorchPreview")
		end,
	})
	table.insert(new, {
		id = "panel.Settings.new",
		run = function(c)
			open(c, "Settings")
		end,
	})
	-- Objectifs › Accueil à mi-parcours (étapes faites ET à faire) : après les 11 étapes jouées plus
	-- haut, l'onglet n'était montré que tout fait (revue de l'outil). En dernier : l'état de
	-- l'accueil ainsi reculé ne touche aucun autre écran du groupe
	table.insert(new, {
		id = "panel.Objectives.onboarding.partial",
		run = function(c)
			closeAll(c)
			c.h:fireClient(
				REMOTES .. "DataPatch",
				{ onboarding = { step = 5, done = false, demoDone = true } },
				{}
			)
			frames(c, 3, 0.1)
			open(c, "Objectives", "onboarding")
		end,
	})
	table.insert(groups, { id = "new", state = "new", screens = new })

	-- Milieu de partie : HUD dans chaque mode, chaque panneau et onglet, cartes, retour
	local mid = { hudScreen("hud.mid") }
	for _, s in hudModes() do
		table.insert(mid, s)
	end
	for _, s in panelScreens("mid") do
		table.insert(mid, s)
	end
	for _, s in cardScreens() do
		table.insert(mid, s)
	end
	table.insert(groups, { id = "mid", state = "mid", screens = mid })

	-- Fin de partie : niveaux au maximum, tout possédé (identifiants suffixés « .late »)
	local late = { hudScreen("hud.late") }
	for _, s in panelScreens("late") do
		s.id ..= ".late"
		table.insert(late, s)
	end
	table.insert(groups, { id = "late", state = "late", screens = late })

	-- Très grands nombres : 1e6 … 999 Dc (dernier suffixe), puis 1,23e36 (notation scientifique)
	local huge = {}
	for _, v in { 1.23456789e6, 1.23456789e12, 9.87654321e17, 4.56e33, 9.99e35, 1.23e36 } do
		local tag = string.gsub(string.format("%.0e", v), "%+", "")
		table.insert(
			huge,
			hudScreen("hud." .. tag, function(c)
				c.h:fireClient(REMOTES .. "DataPatch", { coins = v, pot = v, fame = v }, {})
				frames(c, 4, 0.1)
			end)
		)
	end
	for _, id in { "pads", "pens" } do
		table.insert(huge, {
			id = "panel.Ranch." .. id .. ".huge",
			run = function(c)
				open(c, "Ranch", id)
			end,
		})
	end
	table.insert(huge, {
		id = "panel.SplorchPreview.huge",
		run = function(c)
			open(c, "SplorchPreview")
		end,
	})
	table.insert(huge, {
		id = "panel.Leaderboards.stamps.huge",
		run = function(c)
			leaderboards(c, true)
			open(c, "Leaderboards", "stamps")
		end,
	})
	table.insert(huge, {
		id = "return.huge",
		run = function(c)
			closeAll(c)
			flushAll(c)
			c.h:fireClient(REMOTES .. "Celebrate", {
				kind = "return",
				data = {
					seconds = 7 * 24 * 3600 - 1,
					uid = "u1",
					species = longestSpecies(c),
					grew = 9.99e35,
					pot = 9.99e35,
					splorchReady = true,
					nearlyReady = false,
				},
			})
			frames(c, 30, 0.1)
		end,
	})
	table.insert(groups, { id = "huge", state = "huge", screens = huge })

	-- Retours passagers : bannières (toutes), messages les plus longs, toasts
	local fx = {}
	-- messages de célébration du HUD (emplacement de message)
	for _, entry in
		{
			{ "saddle", {} },
			{ "unlock", { kind = "title", id = "plops_best_friend" } },
			{ "purchase", { key = "SquishParty" } },
			{ "clapCount", { n = 99 } },
			{
				"ownerReturn",
				{ species = 1, coins = 1.23456789e18, catcherId = 3, catcherName = Screens.LONG_NAME_2 },
			},
			{ "returnedBigger", { species = 1 } },
		}
	do
		table.insert(fx, {
			id = "message." .. entry[1],
			run = function(c)
				closeAll(c)
				flushAll(c)
				local data = table.clone(entry[2])
				if data.species then
					data.species = longestSpecies(c)
				end
				c.h:fireClient(REMOTES .. "Celebrate", { kind = entry[1], data = data })
				frames(c, 4, 0.1)
			end,
		})
	end
	-- tampons à l'écran et textes flottants des effets (VFXController), variables les plus longues
	local STAMPS = {
		{ "celebrate.streakMax", { n = 5 } },
		{ "celebrate.perfect" },
		-- cote : la plus rare que le jeu peut écrire, comme il l'écrit (stampOdds)
		{ "celebrate.flop", { odds = true } },
		{ "celebrate.glitch", { odds = true } },
		{ "celebrate.rainbow", { odds = true } },
		{ "celebrate.secretTag", { odds = true }, true },
		{ "celebrate.combo", { n = 5 } },
		{ "celebrate.hero" },
		{ "celebrate.achoo" },
		{ "celebrate.splorchTitle", { roman = "XXVIII" } },
		{ "celebrate.megaSplorch" },
		{ "celebrate.megaFail" },
		{ "celebrate.plopDay", { n = 999 } },
	}
	for _, entry in STAMPS do
		table.insert(fx, {
			id = "stamp." .. string.sub(entry[1], 11),
			run = function(c)
				closeAll(c)
				flushAll(c)
				local VFX = c.h:require(CLIENT .. "Controllers.VFXController")
				local vars = if entry[2] then table.clone(entry[2]) else nil
				if entry[3] then
					vars.species = c.Prefs.t("species." .. c.Species.ById[longestSpecies(c)].key)
				end
				if vars and vars.odds == true then
					vars.odds = stampOdds(c, string.sub(entry[1], 11))
				end
				VFX.stamp(entry[1], vars)
				frames(c, 3, 0.05)
			end,
		})
	end
	local FLOATS = {
		{ "celebrate.plus", { n = "number" } },
		{ "celebrate.hatch", { species = true } },
		{ "celebrate.newEntry" },
		{ "celebrate.star", { n = 5 } },
		{ "celebrate.catch", { species = true } },
		{ "celebrate.babyGet", { species = true } },
		{ "celebrate.splorchBack", { name = true } },
		{ "celebrate.giftShort", { name = Screens.LONG_NAME_2 } },
		{ "celebrate.giftRain", { name = Screens.LONG_NAME_2 } },
		{ "celebrate.luckyDrop" },
		{ "celebrate.lunarDrop" },
		{ "celebrate.objectiveDone" },
		{ "celebrate.perfectStreak", { n = 5 } },
		{ "celebrate.twin" },
	}
	for _, entry in FLOATS do
		table.insert(fx, {
			id = "float." .. string.sub(entry[1], 11),
			run = function(c)
				closeAll(c)
				flushAll(c)
				-- textes flottants précédents terminés
				frames(c, 6, 0.5)
				local VFX = c.h:require(CLIENT .. "Controllers.VFXController")
				local vars = if entry[2] then table.clone(entry[2]) else nil
				local speciesName = c.Prefs.t("species." .. c.Species.ById[longestSpecies(c)].key)
				for k, v in vars or {} do
					if v == true then
						vars[k] = speciesName
					elseif v == "number" then
						vars[k] = c.BigNumber.abbreviate(1.23456789e18, c.lang)
					end
				end
				local pos = c.WorldLayout.spawnCFrame(1).Position + Vector3.new(0, 6, 0)
				VFX.floatText(pos, c.Prefs.t(entry[1], vars))
				frames(c, 2, 0.05)
			end,
		})
	end

	-- aperçu du Grand Splorch hors de son ranch (« Rentre dans ton ranch »)
	table.insert(fx, {
		id = "panel.SplorchPreview.away",
		run = function(c)
			c.h:moveTo(c.h.localPlayer, Vector3.new(0, 3, 0))
			frames(c, 4, 0.1)
			open(c, "SplorchPreview")
			-- dernier écran du groupe : le joueur reste hors de son ranch
		end,
	})
	table.insert(fx, { id = "banner.all", banners = true })
	table.insert(fx, { id = "feedback.all", feedback = true })
	table.insert(groups, { id = "fx", state = "mid", screens = fx })

	-- v2.0 (lot B2) : écran Améliorations, chaque onglet et chaque état atteignable sans achat
	table.insert(groups, { id = "upgrades", state = "mid", screens = upgradeScreens() })
	-- v2.0 (lot B2, étape 4) : HUD v2.0 et rail
	table.insert(groups, { id = "hudv2", state = "mid", screens = hudV2Screens() })
	-- v2.0 (lot B4) : textes du monde du ranch qui évolue
	table.insert(groups, { id = "world", state = "mid", screens = worldScreens() })
	-- v2.0 (lot B3) : écrans de renaissance et de méta
	table.insert(groups, { id = "meta", state = "mid", screens = metaScreens() })
	-- v2.0 (lot B5) : la vie des squishies (textes nouveaux du lot)
	table.insert(groups, { id = "life", state = "mid", screens = lifeScreens() })

	return groups
end

-- Liste à plat des écrans d'un groupe (« banner.all », « feedback.all » développés)
function Screens.expand(c, group)
	local out = {}
	for _, screen in group.screens do
		if screen.feedback then
			for _, s in Screens.feedbackScreens(c) do
				table.insert(out, s)
			end
		elseif screen.banners then
			for _, s in Screens.bannerScreens(c) do
				table.insert(out, s)
			end
		else
			table.insert(out, screen)
		end
	end
	return out
end

-- Amène l'interface dans l'état de l'écran ; retourne ok, erreur
function Screens.show(c, screen)
	if c.EventClock and not screen.event then
		pcall(calm, c)
	end
	local ok, err = pcall(screen.run, c)
	return ok, if ok then nil else tostring(err)
end

-- ---------------------------------------------------------------------------------------------
-- Mesures
-- ---------------------------------------------------------------------------------------------

Screens.LAYOUT_OPTIONS = { fidelity = true, measureText = TextFit.measureAuto }
-- textes du monde : AbsoluteSize écrit (Layout.applyRoot), comme Roblox le fait pour un BillboardGui
Screens.BILLBOARD_OPTIONS = { fidelity = true, measureText = TextFit.measureAuto, absoluteSize = true }

-- Deux passes : le jeu réagit aux tailles écrites (AbsoluteSize) avant la mesure finale
function Screens.layout(c)
	Layout.apply(c.h, Screens.LAYOUT_OPTIONS)
	c.h:settle(1)
	Layout.apply(c.h, Screens.LAYOUT_OPTIONS)
end

function Screens.rootScale(c): number
	return c.Root.scale()
end

-- Écran de chargement (src/first/Loading.client, autonome) : harnais sans client ; `failed` :
-- délai dépassé (bouton Réessayer)
function Screens.bootLoading(Harness, profile, lang: string, failed: boolean)
	EngineProps.install()
	local h = Harness.new({
		mode = "client",
		console = profile.console == true,
		viewport = Vector2.new(profile.w, profile.h),
	})
	h.localPlayer.LocaleId = if lang == "fr" then "fr-fr" else "en-us"
	MockInstance.classMethods.ReplicatedFirst = { RemoveDefaultLoadingScreen = function() end }
	local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
	Clock.freeze(T0)
	h:run("ReplicatedFirst.Loading")
	MockInstance.classMethods.ReplicatedFirst = nil
	local c = {
		h = h,
		Clock = Clock,
		profile = profile,
		lang = lang,
		state = "loading",
		players = {},
		keyOfText = {},
	}
	h:step(1 / 30, 20)
	if failed then
		-- écran d'échec puis « Réessayer » (au plus RETRY_MAX_WAIT = 60 s d'images après l'ouverture)
		h:step(1, 62)
	end
	h:settle(2)
	c.Strings = h:require("ReplicatedStorage.Shared.Localization.Strings")
	c.Root = {
		scale = function()
			local Platform = h:require(CLIENT .. "Util.Platform")
			return Platform.uiScale(Vector2.new(profile.w, profile.h))
		end,
	}
	-- textes recopiés par l'écran de chargement (loading.wake, loading.retry)
	for _, key in { "loading.wake", "loading.retry" } do
		c.keyOfText[c.Strings[lang][key]] = { [key] = false }
	end
	return c
end

-- Objets texte visibles de PlayerGui (chaîne Visible, écran activé, transparence < 1)
function Screens.visibleTexts(c)
	local out = {}
	local playerGui = c.h.localPlayer:FindFirstChildOfClass("PlayerGui")
	for _, d in playerGui:GetDescendants() do
		if
			TextFit.isText(d)
			and Layout.visible(d)
			and Layout.rect(d) ~= nil
			and (EngineProps.get(d, "TextTransparency") or 0) < 0.99
		then
			table.insert(out, d)
		end
	end
	return out
end

-- « ? » montré à la place d'une donnée (nom, espèce, nombre manquant). Les silhouettes voulues
-- (espèce inconnue du Squishydex) ne comptent pas.
local SILHOUETTES = { Q = true, Mark = true, Unknown = true }
function Screens.isQuestion(obj, trimmed: string): boolean
	if trimmed == "?" then
		return not SILHOUETTES[obj.Name]
	end
	return string.sub(trimmed, 1, 2) == "? "
end

local function isKey(c, text)
	return c.Strings.en[text] ~= nil
end

-- Plus long nombre GROUPÉ d'un texte, en chiffres (« 1 000 000 » : 7, « 99 999 » : 5, « 1,23M » : 0) :
-- des chiffres puis au moins un groupe « séparateur + 3 chiffres » (espace, virgule, insécables)
local GROUP_SEPS = { " ", ",", "\194\160", "\226\128\175" }
local function groupedDigits(text: string): number
	local best = 0
	local i = 1
	while i <= #text do
		local a, b = string.find(text, "^%d+", i)
		if a == nil or b == nil then
			i += 1
		else
			local digits = b - a + 1
			local j = b + 1
			local grouped = false
			local matched = true
			while matched do
				matched = false
				for _, sep in GROUP_SEPS do
					if string.sub(text, j, j + #sep - 1) == sep then
						local c, d = string.find(text, "^%d%d%d", j + #sep)
						if c and d and not string.find(string.sub(text, d + 1, d + 1), "%d") then
							digits += 3
							j = d + 1
							grouped = true
							matched = true
							break
						end
					end
				end
			end
			if grouped then
				best = math.max(best, digits)
			end
			i = j
		end
	end
	return best
end

-- Nombres écrits comme le jeu les écrit (Logic/BigNumber) : abrégés à partir de 100 000 avec les
-- suffixes internationaux K M B T Qa Qi Sx Sp Oc No Dc (GDD v1.3 §4.2), virgule décimale et espace
-- fine insécable en français (« 1,23 M »), point en anglais (« 1.23M »). Le panneau Diagnostics
-- (administrateurs, valeurs exactes faites pour être photographiées) n'est pas concerné.
function Screens.numberIssue(c, obj, text: string): string?
	if string.find(Layout.name(obj), "Panel_Diagnostics", 1, true) then
		return nil
	end
	local plain = string.gsub(text, "#%d+", "") -- alias « Squishy Fan #8899 »
	if string.find(plain, "%d%d%d%d%d%d") then
		return "nombre de 6 chiffres ou plus sans abréviation"
	end
	-- même règle pour un nombre GROUPÉ (« 1 000 000 », « 123,456 », espaces insécables comprises) :
	-- le jeu abrège dès 10 000 (BigNumber) et les Confettis dès 100 000 ; la règle des chiffres collés
	-- ne le voyait pas (relecture B1 : le scénario des tampons écrivait « 1 000 000 000 » en dur)
	if groupedDigits(plain) >= 6 then
		return "nombre groupé de 6 chiffres ou plus (« 1 000 000 ») : le jeu l'abrège (BigNumber)"
	end
	local lang = c.lang
	if lang == "en" and string.find(plain, "%d,%d+%s?[KMBTQSOND]") then
		return "virgule décimale française dans un texte anglais"
	end
	if lang == "fr" and string.find(plain, "%d%.%d+%s?[KMBTQSOND]") then
		return "point décimal anglais dans un texte français"
	end
	-- tout nombre décimal, pas seulement devant un suffixe (« 52.0 % », « ×1.5 » du Guide : revue de
	-- l'outil)
	if lang == "fr" and string.find(plain, "%d%.%d") then
		return "point décimal anglais dans un texte français (« 52.0 % » → « 52,0 % »)"
	end
	if string.find(plain, "%d%s?Md%f[%A]") or string.find(plain, "%d%s?k%f[%A]") then
		return "suffixe hors de la liste du jeu (k, Md : ancien format)"
	end
	return nil
end

-- Clés de localisation d'un texte affiché (toutes les traductions qui ont produit exactement ce
-- texte) : { [clé] = variables | false }
function Screens.keysOf(c, text: string)
	return c.keyOfText and c.keyOfText[text]
end

-- Une clé (la première par ordre alphabétique) d'un texte affiché, ou nil
function Screens.keyOf(c, text: string)
	local set = Screens.keysOf(c, text)
	if set == nil then
		return nil
	end
	local best = nil
	for key in set do
		if best == nil or key < best then
			best = key
		end
	end
	return best
end

-- Textes des BillboardGui du monde (et de PlayerGui), mis en page à leur taille en pixels comme
-- ScreenDump (Layout.applyRoot) : { obj } ; Layout.rect(obj) est alors celui de la plaque
Screens.BILLBOARD_DISTANCE = 24
function Screens.billboardTexts(c)
	local out = {}
	local h = c.h
	local pxPerStud = c.profile.h / (2 * Screens.BILLBOARD_DISTANCE * math.tan(math.rad(35)))
	local list = {}
	for _, d in h.game.Workspace:GetDescendants() do
		if d.ClassName == "BillboardGui" then
			table.insert(list, d)
		end
	end
	for _, bb in list do
		if EngineProps.get(bb, "Enabled") ~= false then
			local size = EngineProps.get(bb, "Size")
			local w = size.X.Offset + size.X.Scale * pxPerStud
			local hh = size.Y.Offset + size.Y.Scale * pxPerStud
			if w >= 2 and hh >= 2 then
				-- deux passes (lot B4, étape 5) : la première écrit AbsoluteSize (les icônes dessinées de
				-- UI/Text se replacent d'après la vraie boîte de leur libellé), la seconde les met en page
				Layout.applyRoot(bb, w, hh, Screens.BILLBOARD_OPTIONS)
				h:settle(1)
				Layout.applyRoot(bb, w, hh, Screens.BILLBOARD_OPTIONS)
				for _, d in bb:GetDescendants() do
					if
						TextFit.isText(d)
						and Layout.rect(d) ~= nil
						and (EngineProps.get(d, "TextTransparency") or 0) < 0.99
					then
						local visible = true
						local cur = d
						while cur ~= nil and cur ~= bb do
							if cur:IsA("GuiObject") and cur.Visible == false then
								visible = false
								break
							end
							cur = cur.Parent
						end
						if visible then
							table.insert(out, d)
						end
					end
				end
			end
		end
	end
	return out
end

-- Problèmes de texte de l'écran courant (après Screens.layout) :
--   { path, text, kind, message, realSize, scaled, key }
-- kinds : overflow, splitWord, truncated, small, orphan (TextFit.fits), rawKey (clé de localisation
-- affichée), placeholder (« {variable} » brute), question (« ? » seul), defaultText (texte jamais
-- posé : « Label » / « Button » du moteur)
function Screens.textIssues(c, opts)
	opts = opts or {}
	local rootScale = Screens.rootScale(c)
	local out = {}
	local objs = Screens.visibleTexts(c)
	if c.WorldLayout then
		for _, obj in Screens.billboardTexts(c) do
			table.insert(objs, obj)
		end
	end
	for _, obj in objs do
		local ok, d = TextFit.fits(obj, { rootScale = rootScale })
		local path = Layout.name(obj)
		local key = Screens.keyOf(c, d and d.text or "")
		local function add(kind, message)
			table.insert(out, {
				path = path,
				text = d and d.text or "",
				kind = kind,
				message = message,
				realSize = d and d.realSize or 0,
				scaled = d ~= nil and d.scaled == true,
				key = key,
			})
		end
		if not ok then
			for _, issue in d.issues do
				add(issue.kind, issue.message)
			end
		end
		local text = d and d.text or ""
		local trimmed = string.gsub(string.gsub(text, "^%s+", ""), "%s+$", "")
		if Screens.isQuestion(obj, trimmed) then
			add("question", "« ? » affiché au joueur à la place d'une donnée")
		elseif isKey(c, trimmed) then
			add("rawKey", "clé de localisation affichée telle quelle")
		elseif string.find(text, "{%w+}") then
			add("placeholder", "variable non remplacée")
		end
		local numberIssue = Screens.numberIssue(c, obj, text)
		if numberIssue then
			add("numberFormat", numberIssue)
		end
		if not EngineProps.written(obj, "Text") and obj.ClassName ~= "TextBox" then
			add(
				"defaultText",
				"texte jamais posé : le moteur affiche « "
					.. tostring(EngineProps.get(obj, "Text"))
					.. " »"
			)
		end
	end
	table.sort(out, function(a, b)
		if a.path ~= b.path then
			return a.path < b.path
		end
		return a.kind < b.kind
	end)
	return out
end

-- Boîtes de texte de l'écran courant reliées à une clé (TextFit_keys) : { key, vars, box }
-- box = { w, h (px de mise en page, UIPadding retiré), k, font, scaled, wrapped, minS, maxS, lh,
-- size, trunc, path }
function Screens.keyBoxes(c)
	local out = {}
	local objs = Screens.visibleTexts(c)
	if c.WorldLayout then
		for _, obj in Screens.billboardTexts(c) do
			table.insert(objs, obj)
		end
	end
	for _, obj in objs do
		local d = TextFit.layout(obj)
		-- lot B1 : texte d'origine d'un libellé à repères de UI/Text (« {_} », « {*} »), relié à sa clé
		local source = obj:GetAttribute("TextSource")
		local shownText = if type(source) == "string" then source elseif d then d.text else ""
		local set = if d and d.text ~= "" then Screens.keysOf(c, shownText) else nil
		if set == nil and d and d.text ~= "" and string.find(shownText, " · ", 1, true) then
			-- lot B4, étape 5 : texte du monde fait de morceaux traduits séparés par « · » (panneau des
			-- ranchs : nom, Record R, « Jour 42 », badge, « PRÊT ! ») : chaque morceau traduit est relié à
			-- sa clé et mesuré dans la boîte du texte entier (le texte entier est vérifié tel quel par
			-- textIssues, dans les deux langues)
			for segment in string.gmatch(shownText .. " · ", "(.-) · ") do
				local part = Screens.keysOf(c, segment)
				if part then
					set = set or {}
					for key, vars in part do
						set[key] = vars
					end
				end
			end
		end
		-- lot B3, étape 2 : variable-clé (UI/MetaView.resolve) : une variable dont la valeur est ELLE-MÊME le
		-- texte d'une clé (nom d'un ciel, d'un objet, d'une Plopette dans « Halo et ciel : {name} ») relie
		-- aussi cette clé à la boîte (sa traduction y est mesurée seule ; le texte entier l'est par la clé
		-- extérieure, avec la variable vue) ; une valeur sans lettre (nombre) n'est jamais une clé
		if set then
			local merged = nil
			for _, vars in set do
				if type(vars) == "table" then
					for _, v in vars do
						local inner = if type(v) == "string" and string.find(v, "%a")
							then Screens.keysOf(c, v)
							else nil
						if inner then
							for k2, vars2 in inner do
								if set[k2] == nil then
									merged = merged or table.clone(set)
									merged[k2] = vars2
								end
							end
						end
					end
				end
			end
			set = merged or set
		end
		-- texte "fit" de UI/Text (lot B1) : le jeu reprend la règle de l'ancien TextScaled pour chaque
		-- texte posé (plus grande taille entière de [TextFitMin, TextFitMax] qui tient) ; toute clé est
		-- donc mesurée dans la boîte avec cette règle, pas à la taille relevée pour le texte affiché
		local fitMin, fitMax = obj:GetAttribute("TextFitMin"), obj:GetAttribute("TextFitMax")
		local fit = type(fitMin) == "number" and type(fitMax) == "number"
		for key, vars in set or {} do
			do
				local truncate = EngineProps.get(obj, "TextTruncate")
				table.insert(out, {
					key = key,
					vars = if vars then vars else nil,
					box = {
						path = Layout.name(obj),
						w = d.boxW,
						h = d.boxH,
						k = d.k,
						font = d.font,
						scaled = d.scaled or fit,
						wrapped = d.wrapped,
						minS = if fit then fitMin else d.minSize,
						maxS = if fit then fitMax else d.maxSize,
						lh = EngineProps.get(obj, "LineHeight") or 1,
						size = if d.scaled or fit then nil else d.size,
						trunc = if truncate then truncate.Name else "None",
						deco = d.decorative,
					},
				})
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------------------------------------
-- Contrôles d'affichage hors texte (Screens_*.spec) : contraste, fenêtres, curseur, teinte
-- ---------------------------------------------------------------------------------------------

local function channel(v: number): number
	return if v <= 0.03928 then v / 12.92 else ((v + 0.055) / 1.055) ^ 2.4
end

local function luminance(c): number
	return 0.2126 * channel(c.R) + 0.7152 * channel(c.G) + 0.0722 * channel(c.B)
end

-- Rapport de contraste WCAG entre deux Color3
function Screens.contrast(a, b): number
	local la, lb = luminance(a), luminance(b)
	if la < lb then
		la, lb = lb, la
	end
	return (la + 0.05) / (lb + 0.05)
end

local function mixColor(top, bottom, alpha)
	return roblox.Color3.new(
		top.R * alpha + bottom.R * (1 - alpha),
		top.G * alpha + bottom.G * (1 - alpha),
		top.B * alpha + bottom.B * (1 - alpha)
	)
end

-- Fond réellement dessiné derrière un objet : composition des fonds (BackgroundColor3,
-- BackgroundTransparency) de l'objet et de ses ancêtres, du plus proche fond opaque jusqu'à lui ;
-- nil si aucun fond opaque (le monde 3D derrière : inconnu)
function Screens.backdrop(obj)
	local layers = {}
	local cur = obj
	while cur ~= nil and cur:IsA("GuiObject") do
		local t = EngineProps.get(cur, "BackgroundTransparency") or 0
		if t < 0.99 then
			table.insert(layers, { color = EngineProps.get(cur, "BackgroundColor3"), alpha = 1 - t })
			if t <= 0.1 then
				break
			end
		end
		cur = cur.Parent
	end
	local base = nil
	for i = #layers, 1, -1 do
		local l = layers[i]
		if base == nil then
			if l.alpha < 0.9 then
				return nil
			end
			base = l.color
		else
			base = mixColor(l.color, base, l.alpha)
		end
	end
	return base
end

-- Textes visibles (non décoratifs, avec une lettre ou un chiffre) dont le contraste avec leur fond
-- est < 3 (WCAG, grand texte), contour du texte compté (UIStroke Contextual, TextStroke)
function Screens.contrastIssues(c, root)
	local out = {}
	for _, obj in Screens.visibleTexts(c) do
		if (root == nil or obj:IsDescendantOf(root)) and not TextFit.decorative(obj) then
			local text = TextFit.displayText(obj)
			if string.find(text, "[%w\128-\255]") then
				local bg = Screens.backdrop(obj)
				if bg ~= nil then
					local tc = EngineProps.get(obj, "TextColor3")
					local ratio = Screens.contrast(tc, bg)
					for _, ch in obj:GetChildren() do
						if
							ch.ClassName == "UIStroke"
							and EngineProps.get(ch, "Enabled") ~= false
							and EngineProps.get(ch, "ApplyStrokeMode") ~= Enum.ApplyStrokeMode.Border
							and (EngineProps.get(ch, "Transparency") or 0) < 0.5
							and (EngineProps.get(ch, "Thickness") or 1) >= 1
						then
							ratio = math.max(ratio, Screens.contrast(tc, EngineProps.get(ch, "Color")))
						end
					end
					if (EngineProps.get(obj, "TextStrokeTransparency") or 1) < 0.5 then
						ratio =
							math.max(ratio, Screens.contrast(tc, EngineProps.get(obj, "TextStrokeColor3")))
					end
					if ratio < 3 then
						table.insert(
							out,
							string.format(
								"contraste %.2f < 3 : %s « %s » (texte %d,%d,%d sur %d,%d,%d)",
								ratio,
								Layout.name(obj),
								string.sub(text, 1, 40),
								math.floor(tc.R * 255 + 0.5),
								math.floor(tc.G * 255 + 0.5),
								math.floor(tc.B * 255 + 0.5),
								math.floor(bg.R * 255 + 0.5),
								math.floor(bg.G * 255 + 0.5),
								math.floor(bg.B * 255 + 0.5)
							)
						)
					end
				end
			end
		end
	end
	table.sort(out)
	return out
end

-- Fenêtres (panneaux « Panel_* », écran de retour, cartes) : aucun objet visible n'en dépasse
-- (sélection comprise : un bouton qui grandit quand il est choisi reste dans sa fenêtre)
function Screens.windowIssues(c)
	local out = {}
	local gui = c.h.localPlayer.PlayerGui
	local windows = {}
	local panels = gui:FindFirstChild("Panels")
	if panels and panels:FindFirstChild("Safe") then
		for _, w in panels.Safe:GetChildren() do
			if string.sub(w.Name, 1, 6) == "Panel_" and Layout.visible(w) then
				table.insert(windows, w)
			end
		end
	end
	for _, w in windows do
		local wr = Layout.rect(w)
		if wr then
			for _, d in w:GetDescendants() do
				if d:IsA("GuiObject") and Layout.visible(d) and not TextFit.decorative(d) then
					local r = Layout.rect(d)
					if r and r.w > 2 and r.h > 2 then
						-- partie visible (découpe des ancêtres : liste défilante)
						local x0, y0, x1, y1 = r.x, r.y, r.x + r.w, r.y + r.h
						if r.clip then
							x0, y0 = math.max(x0, r.clip.x), math.max(y0, r.clip.y)
							x1, y1 = math.min(x1, r.clip.x + r.clip.w), math.min(y1, r.clip.y + r.clip.h)
						end
						if x1 > x0 and y1 > y0 then
							local over =
								math.max(wr.x - x0, wr.y - y0, x1 - (wr.x + wr.w), y1 - (wr.y + wr.h))
							if over > 1.5 then
								table.insert(
									out,
									string.format(
										"%s dépasse de sa fenêtre %s de %.0f px",
										Layout.name(d),
										w.Name,
										over
									)
								)
							end
						end
					end
				end
			end
		end
	end
	table.sort(out)
	return out
end

-- Curseur de sélection : objet visible, halo (débord du cadre de sélection) entier à l'écran et pas
-- caché par un parent qui découpe
function Screens.selectionIssues(c)
	local selected = c.h.game.GuiService.SelectedObject
	if selected == nil then
		return {}
	end
	if not Layout.visible(selected) then
		return { "objet sélectionné invisible : " .. Layout.name(selected) }
	end
	local r = Layout.rect(selected)
	if r == nil then
		return {}
	end
	local o = 0
	local image = selected.SelectionImageObject
	if image then
		o = (image.Size.X.Offset / 2) * (r.k or 1)
	end
	local x0, y0, x1, y1 = r.x - o, r.y - o, r.x + r.w + o, r.y + r.h + o
	local out = {}
	local vw, vh = c.profile.w, c.profile.h
	if x0 < -1 or y0 < -1 or x1 > vw + 1 or y1 > vh + 1 then
		table.insert(out, "curseur hors de l'écran : " .. Layout.name(selected))
	end
	if r.clip then
		local cx0, cy0 = math.max(x0, r.clip.x), math.max(y0, r.clip.y)
		local cx1, cy1 = math.min(x1, r.clip.x + r.clip.w), math.min(y1, r.clip.y + r.clip.h)
		local shown = math.max(0, cx1 - cx0) * math.max(0, cy1 - cy0)
		if shown < 0.5 * (x1 - x0) * (y1 - y0) then
			table.insert(out, "curseur caché par un parent qui découpe : " .. Layout.name(selected))
		end
	end
	return out
end

-- Textes coupés par un parent qui découpe (ClipsDescendants) : une partie seulement de la ligne est
-- visible (entre 5 % et 95 % de sa hauteur). Les rangées entrouvertes voulues des listes virtuelles
-- (attribut PeekRows, Widgets.rows) ne comptent pas.
function Screens.clipIssues(c)
	local out = {}
	for _, obj in Screens.visibleTexts(c) do
		local r = Layout.rect(obj)
		if r and r.clip and not TextFit.decorative(obj) and string.find(TextFit.displayText(obj), "%S") then
			local y0, y1 = math.max(r.y, r.clip.y), math.min(r.y + r.h, r.clip.y + r.clip.h)
			local shown = math.max(0, y1 - y0) / math.max(r.h, 1)
			if shown > 0.05 and shown < 0.95 then
				local peek = false
				local cur = obj.Parent
				while cur ~= nil and cur:IsA("GuiObject") do
					if cur:GetAttribute("PeekRows") == true then
						peek = true
						break
					end
					cur = cur.Parent
				end
				if not peek then
					table.insert(
						out,
						string.format(
							"texte coupé par un parent (%.0f %% visible) : %s « %s »",
							shown * 100,
							Layout.name(obj),
							string.sub(TextFit.displayText(obj), 1, 40)
						)
					)
				end
			end
		end
	end
	table.sort(out)
	return out
end

-- Chevauchements ENTRE écrans : textes visibles de l'écran `top` (ex. le grand tampon VFXStamp) sur
-- les textes et cases visibles des écrans `others` (ex. HUD) ; le texte réellement dessiné compte
-- (mesuré par TextFit, aligné dans sa boîte), pas sa boîte entière
function Screens.crossOverlaps(c, top: string, others: { string })
	local out = {}
	local gui = c.h.localPlayer.PlayerGui
	local topGui = gui:FindFirstChild(top)
	if topGui == nil or topGui.Enabled == false then
		return out
	end
	local function inkOf(obj)
		local r = Layout.rect(obj)
		local d = TextFit.layout(obj)
		if r == nil or d == nil then
			return nil
		end
		local k = r.k or 1
		local w, h = math.min(r.w, d.textWidth * k), math.min(r.h, d.textHeight * k)
		local xa = EngineProps.get(obj, "TextXAlignment")
		local x = r.x + (r.w - w) / 2
		if xa == Enum.TextXAlignment.Left then
			x = r.x
		elseif xa == Enum.TextXAlignment.Right then
			x = r.x + r.w - w
		end
		return { x = x, y = r.y + (r.h - h) / 2, w = w, h = h }
	end
	local tops = {}
	for _, d in topGui:GetDescendants() do
		if TextFit.isText(d) and Layout.visible(d) and string.find(TextFit.displayText(d), "%S") then
			local ink = inkOf(d)
			if ink then
				table.insert(tops, { obj = d, r = ink })
			end
		end
	end
	for _, name in others do
		local g = gui:FindFirstChild(name)
		if g and g.Enabled ~= false then
			for _, d in g:GetDescendants() do
				if d:IsA("GuiObject") and Layout.visible(d) and not TextFit.decorative(d) then
					local isText = TextFit.isText(d) and string.find(TextFit.displayText(d), "%S") ~= nil
					local r = if isText then inkOf(d) else nil
					if
						r == nil
						and (d:IsA("GuiButton") or (EngineProps.get(d, "BackgroundTransparency") or 0) < 0.5)
					then
						r = Layout.rect(d)
					end
					if r and r.w > 2 and r.h > 2 then
						for _, t in tops do
							local ox = math.min(t.r.x + t.r.w, r.x + r.w) - math.max(t.r.x, r.x)
							local oy = math.min(t.r.y + t.r.h, r.y + r.h) - math.max(t.r.y, r.y)
							if ox > 2 and oy > 2 then
								table.insert(out, Layout.name(t.obj) .. " sur " .. Layout.name(d))
								break
							end
						end
					end
				end
			end
		end
	end
	table.sort(out)
	return out
end

-- Textes et boutons teintés par l'UIGradient d'un CanvasGroup ancêtre (Roblox applique le dégradé
-- d'un CanvasGroup à TOUT son contenu)
function Screens.tintIssues(c)
	local out = {}
	local gui = c.h.localPlayer.PlayerGui
	for _, d in gui:GetDescendants() do
		if (TextFit.isText(d) or d:IsA("GuiButton")) and Layout.visible(d) then
			local cur = d.Parent
			while cur ~= nil and not cur:IsA("LayerCollector") do
				if cur.ClassName == "CanvasGroup" then
					local g = cur:FindFirstChildOfClass("UIGradient")
					if g and EngineProps.get(g, "Enabled") ~= false then
						table.insert(
							out,
							Layout.name(d) .. " teinté par l'UIGradient de " .. Layout.name(cur)
						)
						break
					end
				end
				cur = cur.Parent
			end
		end
	end
	table.sort(out)
	return out
end

return Screens
