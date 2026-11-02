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
local Layout = require("./Layout")
local TextFit = require("./TextFit")
local EngineProps = require("./EngineProps")
local TvAudit = require("./TvAudit")
local Gamepad = require("./Gamepad")
local MockInstance = require("./MockInstance")

local Enum = roblox.Enum
local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3

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
	{ "OutfitPreview", { "sweater", "crown" } },
	{ "Diagnostics", { "server", "client", "today", "tools" } },
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

function Screens.varsFor(c, key, lang)
	lang = lang or c.lang
	local vars = {}
	local strings = c.Strings[lang] or c.Strings.en
	local template = strings[key] or c.Strings.en[key] or ""
	local BN = c.BigNumber or c.h:require("ReplicatedStorage.Shared.Logic.BigNumber")
	c.BigNumber = BN
	for name in string.gmatch(template, "{(%w+)}") do
		if NUMBER_VARS[name] then
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

-- Groupes d'écrans : un client démarré par groupe (état de données), écrans joués dans l'ordre
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
		{ "celebrate.flop", { odds = "1 000 000" } },
		{ "celebrate.glitch", { odds = "1 000 000" } },
		{ "celebrate.rainbow", { odds = "1 000 000" } },
		{ "celebrate.secretTag", { odds = "1 000 000 000" }, true },
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
	local lang = c.lang
	if lang == "en" and string.find(plain, "%d,%d+%s?[KMBTQSOND]") then
		return "virgule décimale française dans un texte anglais"
	end
	if lang == "fr" and string.find(plain, "%d%.%d+%s?[KMBTQSOND]") then
		return "point décimal anglais dans un texte français"
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
				Layout.applyRoot(bb, w, hh, Screens.LAYOUT_OPTIONS)
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
		local set = if d and d.text ~= "" then Screens.keysOf(c, d.text) else nil
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
						scaled = d.scaled,
						wrapped = d.wrapped,
						minS = d.minSize,
						maxS = d.maxSize,
						lh = EngineProps.get(obj, "LineHeight") or 1,
						size = if d.scaled then nil else d.size,
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
