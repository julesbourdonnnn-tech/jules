--!nocheck
-- Scénarios d'écrans : démarre le VRAI client (Main.client) dans le harnais, sur un appareil et
-- dans une langue donnés, lui envoie des charges serveur réalistes (DataSnapshot, DataPatch,
-- EventState, Feedback, Banner, Celebrate, invitations…) et amène l'interface dans chaque état à
-- vérifier. Partagé par l'outil de captures (tools/screens/capture.luau) et la spec
-- tests/specs/TextFit_all.spec.luau.
--
--   local Screens = require("./Screens")
--   for _, group in Screens.groups() do
--       local c = Screens.boot(Harness, profile, "fr", group)
--       for _, screen in group.screens do
--           Screens.show(c, screen)            -- amène l'interface dans l'état
--           Screens.layout(c)                  -- mise en page fidèle (textes mesurés)
--           ... Screens.textIssues(c) / ScreenDump.dump(c, …)
--       end
--   end
--
-- Appareils (PROFILES) : téléviseur console 1920 × 1080, 3840 × 2160 et 1280 × 720 (manette,
-- console), téléphone 844 × 390 et tablette 1024 × 768 (tactile), PC 1366 × 768 (clavier-souris).
-- États : nouveau joueur, milieu de partie, fin de partie, très grands nombres (1e6, 1e12, 1e18,
-- 1e30 Glow et Stardust), niveaux au maximum, noms de joueurs de 20 caractères, chaînes françaises
-- les plus longues (toutes les clés feedback.* et banner.* affichées).

local roblox = require("@lune/roblox")
local Layout = require("./Layout")
local TextFit = require("./TextFit")
local Props = require("./Props")

local Enum = roblox.Enum
local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3

local Screens = {}

local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
local REMOTES = "ReplicatedStorage.Remotes."
local T0 = 1800000000 -- vendredi 15 janvier 2027, 08:00 UTC
local TODAY = math.floor(T0 / 86400)
Screens.T0 = T0
Screens.CLIENT = CLIENT
Screens.REMOTES = REMOTES

-- Noms de joueurs de 20 caractères (DisplayName Roblox : 20 au plus)
Screens.LONG_NAME = "MaximilianWolfgang20"
Screens.LONG_NAME_2 = "WilhelminaMcKenzie99"

Screens.PROFILES = {
	{ id = "tv1080", label = "Console TV 1920×1080", w = 1920, h = 1080, console = true },
	{ id = "tv2160", label = "Console TV 3840×2160", w = 3840, h = 2160, console = true },
	{ id = "tv720", label = "Console TV 1280×720", w = 1280, h = 720, console = true },
	{ id = "phone", label = "Téléphone 844×390 (tactile)", w = 844, h = 390, touch = true },
	{
		id = "tablet",
		label = "Tablette 1024×768 (tactile)",
		w = 1024,
		h = 768,
		touch = true,
		display = "Medium",
	},
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
-- Profils de données (instantanés DataSnapshot réalistes)
-- ---------------------------------------------------------------------------------------------

local MAX_LEVELS = { conga = 57, stride = 20, lure = 12, perches = 27, guard = 5 }
local MID_LEVELS = { conga = 6, stride = 10, lure = 6, perches = 13, guard = 2 }
local ZERO_LEVELS = { conga = 0, stride = 0, lure = 0, perches = 0, guard = 0 }

local function copy(t)
	local out = {}
	for k, v in t do
		out[k] = if type(v) == "table" then copy(v) else v
	end
	return out
end

local function settings(lang)
	return {
		zen = false,
		reducedMotion = false,
		lowGraphics = false,
		music = true,
		sfx = true,
		vibration = true,
		autoCrew = true,
		refuseInvites = false,
		lang = lang,
	}
end

-- Réserve : n Nebbies (espèces 1-36, formes, variantes, étoiles, verrous)
local function nebbies(n, rich)
	local out = {}
	for i = 1, n do
		local s = ((i - 1) % 36) + 1
		local f = if rich then (i // 36) % 6 else 0
		local v = 0
		if rich then
			v = if i % 17 == 0 then 7 elseif i % 11 == 0 then 1 elseif i % 13 == 0 then 2 else 0
		end
		out["u" .. i] = {
			s = s,
			f = f,
			v = v,
			st = if rich then (i % 5) + 1 else 1,
			lk = rich and i % 9 == 0 or nil,
		}
	end
	return out
end

local function atlasWords(fraction)
	local words = {}
	for i = 1, 7 do
		if fraction >= 1 then
			words[i] = if i == 7 then 0xFFFFFF else 0xFFFFFFFF
		elseif fraction <= 0 then
			words[i] = 0
		else
			words[i] = if i <= math.floor(7 * fraction) then 0xFFFFFFFF else 0x5
		end
	end
	return words
end

local function baseProfile(lang)
	return {
		version = 1,
		glow = 0,
		glowCarry = 0,
		lastSettle = T0,
		lastOnline = T0,
		idleRate = 0,
		stardust = 0,
		supernovas = 0,
		upgrades = copy(ZERO_LEVELS),
		boosts = { personalUntil = 0 },
		caps = { day = TODAY, snipDust = 0, wispDust = 0, cheers = 0, duo = false },
		nebbies = {},
		nextUid = 1,
		perchIncome = 0,
		atlas = atlasWords(0),
		badges = { 0, 0, 0, 0 },
		atlasRewards = 0,
		onboarding = { step = 1, p = 0 },
		daily = { day = 0, step = 1 },
		quests = { day = TODAY, list = {}, rerolls = 0, starClaimed = false },
		weekly = { week = 0, banked = 0, claimed = false },
		rookie = { sessions = 1, playSeconds = 30, done = false },
		settings = settings(lang),
		cosmetics = { style = "default", title = "", nestTheme = "default" },
		unlocks = { styles = {}, titles = {}, themes = {} },
		weeklyBest = { week = 0, conga = 0 },
		starterKit = false,
		stats = {
			catches = 0,
			parades = 0,
			longestParade = 0,
			sessions = 1,
			playSeconds = 30,
			fusions = 0,
		},
		passes = {},
	}
end

local DAILY = function(doneClaimable)
	return {
		day = TODAY,
		list = {
			{ id = 1, p = 3, done = false, claimed = false },
			{ id = 2, p = 10, done = doneClaimable, claimed = false },
			{ id = 3, p = 1, done = true, claimed = true },
		},
		rerolls = 0,
		starClaimed = false,
	}
end

-- kind : "new" | "mid" | "late" | "huge"
function Screens.profile(kind: string, lang: string)
	local p = baseProfile(lang)
	if kind == "new" then
		return p
	end
	p.onboarding = { step = 8, p = 0 }
	p.rookie = { sessions = 6, playSeconds = 9000, done = true }
	p.daily = { day = TODAY - 1, step = 3 }
	p.quests = DAILY(true)
	p.weekly = { week = 0, banked = 12, claimed = false }
	p.stats = {
		catches = 1234,
		parades = 98,
		longestParade = 31,
		snipsDealt = 12,
		sessions = 6,
		playSeconds = 9000,
		fusions = 14,
		cometsBanked = 2,
	}
	if kind == "mid" then
		p.glow = 1234567
		p.stardust = 12345
		p.idleRate = 1234
		p.perchIncome = 1234
		p.upgrades = copy(MID_LEVELS)
		p.nebbies = nebbies(60, false)
		p.nebbies.f1 = { s = 2, f = 0, v = 0, st = 1 }
		p.nebbies.f2 = { s = 2, f = 0, v = 0, st = 1 }
		p.nebbies.f3 = { s = 2, f = 0, v = 0, st = 1 }
		p.nextUid = 100
		p.atlas = atlasWords(0.4)
		p.atlasRewards = 10
		return p
	end
	-- fin de partie : niveaux au maximum, Supernova XII, réserve pleine, passes possédés
	p.supernovas = if kind == "huge" then 40 else 12
	p.upgrades = copy(MAX_LEVELS)
	p.glow = if kind == "huge" then 1.23456789e30 else 9.87654321e17
	p.stardust = if kind == "huge" then 1.23456789e30 else 9.87654321e11
	p.idleRate = if kind == "huge" then 9.87e27 else 1.23e15
	p.perchIncome = p.idleRate
	p.nebbies = nebbies(300, true)
	p.nextUid = 400
	p.atlas = atlasWords(1)
	p.badges = { 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF }
	p.atlasRewards = 150
	p.passes = { VIPStar = true, DoubleGlow = true, NightShift = true, ExtraPerches = true, StashPlus = true }
	p.boosts = { personalUntil = T0 + 3599 }
	p.cosmetics = { style = "default", title = "", nestTheme = "default" }
	p.weeklyBest = { week = 0, conga = 57 }
	p.weekly = { week = 0, banked = 999, claimed = false }
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

-- Client complet démarré pour `profile` (entrée de PROFILES), `lang` ("fr" | "en") et l'état de
-- données `state` ("new" | "mid" | "late" | "huge")
function Screens.boot(Harness, profile, lang: string, state: string)
	local h = Harness.new({
		mode = "client",
		console = profile.console == true,
		touch = profile.touch == true,
		viewport = Vector2.new(profile.w, profile.h),
	})
	if profile.display then
		h.game.GuiService.ViewportDisplaySize = Enum.DisplaySize[profile.display]
	end
	local me = h.localPlayer
	me.LocaleId = if lang == "fr" then "fr-fr" else "en-us"
	me.DisplayName = Screens.LONG_NAME
	h:createRemotes()
	-- boutique : tous les articles en vente (ids non nuls), comme en production
	local Monetization = h:require("ReplicatedStorage.Shared.Config.Monetization")
	local nextId = 900001
	for _, group in { Monetization.Passes, Monetization.Products } do
		local keys = {}
		for key in group do
			table.insert(keys, key)
		end
		table.sort(keys)
		for _, key in keys do
			group[key].id = nextId
			nextId += 1
		end
	end
	local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
	Clock.freeze(T0)
	h:find(REMOTES .. "RedeemCode").OnServerInvoke = function()
		return "ok"
	end
	h:boot()
	local data = Screens.profile(state, lang)
	h:fireClient(REMOTES .. "DataSnapshot", data)
	h:step(1 / 60, 30)
	h:settle(3)
	local c = {
		h = h,
		Clock = Clock,
		profile = profile,
		lang = lang,
		state = state,
		data = data,
		PC = h:require(CLIENT .. "Controllers.PanelController"),
		HUD = h:require(CLIENT .. "UI.HUD"),
		Root = h:require(CLIENT .. "UI.Root"),
		Toast = h:require(CLIENT .. "UI.Toast"),
		Banners = h:require(CLIENT .. "UI.Banners"),
		FX = h:require(CLIENT .. "UI.ScreenFX"),
		Minimap = h:require(CLIENT .. "UI.Minimap"),
		Prefs = h:require(CLIENT .. "Util.Prefs"),
		WSC = h:require(CLIENT .. "Controllers.WorldStateController"),
		Strings = h:require("ReplicatedStorage.Shared.Localization.Strings"),
		Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
		WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
		Monetization = Monetization,
		players = {},
	}
	-- joueurs du serveur aux noms longs (Équipage, bannières, Comète)
	for i, name in { Screens.LONG_NAME_2, "Léa", "Noah", "ÉlodieBérénice2026" } do
		local p = h:addPlayer({ userId = i + 1, name = name })
		p.DisplayName = name
		table.insert(c.players, p)
	end
	me:SetAttribute("Slot", 1)
	frames(c, 10)
	return c
end

local function panel(c, name)
	return c.h:require(CLIENT .. "UI.Panels." .. name)
end
Screens.panel = panel

function Screens.patch(c, data, entries)
	c.h:fireClient(REMOTES .. "DataPatch", data, {}, entries)
	frames(c, 4)
end

local function goHome(c)
	local me = c.h.localPlayer
	me:SetAttribute("Slot", 1)
	local gate = c.WorldLayout.gateCFrame(1).Position
	if me.Character and me.Character:FindFirstChild("HumanoidRootPart") then
		me.Character.HumanoidRootPart.CFrame = CFrame.new(gate.X, 3, gate.Z)
	end
end

local function goAway(c)
	local me = c.h.localPlayer
	if me.Character and me.Character:FindFirstChild("HumanoidRootPart") then
		me.Character.HumanoidRootPart.CFrame = CFrame.new(0, 3, 30)
	end
end

-- Panneau ouvert depuis le jeu (fermé avant), comme au rail
local function open(c, name, args)
	c.PC.close()
	frames(c, 8)
	c.h.game.GuiService.SelectedObject = nil
	c.PC.open(name, args)
	frames(c, 10)
end
Screens.open = open

local function closeAll(c)
	c.PC.close()
	frames(c, 8)
	c.h.game.GuiService.SelectedObject = nil
end

-- Bannière en cours terminée et file vidée (Clock du jeu)
local function flushBanners(c)
	for _ = 1, 12 do
		if c.Banners.current() == nil and #c.Banners.queued() == 0 then
			break
		end
		c.Clock.advance(12)
		frames(c, 3)
	end
end

-- Effets passagers (cartes, tampons, floaters, confettis, toasts) terminés
local function flushFx(c)
	-- 6 s d'animation : cartes « NOUVEAU ! » (entrée + tenue + sortie), tampons, titres
	for _ = 1, 12 do
		c.Clock.advance(0.5)
		c.h:step(0.5, 1)
	end
	local toasts = c.h.localPlayer.PlayerGui:FindFirstChild("Toasts")
	if toasts then
		-- toasts (3 s réelles) : remplacés par des toasts vides puis cachés ; jamais détruits ici (le
		-- module garde sa liste)
		for _, t in toasts.Safe.Stack:GetChildren() do
			if t.Name == "Toast" then
				t.Visible = false
			end
		end
	end
	frames(c, 2)
end
Screens.flushFx = flushFx

local function eventState(c, over)
	local payload = {
		t = c.Clock.now(),
		wisps = {},
		snipsDisabled = false,
		activePlayers = 5,
	}
	for k, v in over or {} do
		payload[k] = v
	end
	c.h:fireClient(REMOTES .. "EventState", payload)
	frames(c, 6)
end

local function cheer(c)
	c.HUD._onCheerPrompt({ heroId = c.players[1].UserId, level = 12, expiresAt = c.Clock.now() + 10 })
	frames(c, 3)
end

local function codeOf(c, s, f, v)
	return c.Nebbies.pack(s, f or 0, v or 0)
end

-- ---------------------------------------------------------------------------------------------
-- Valeurs d'essai des variables de textes (les plus longues plausibles)
-- ---------------------------------------------------------------------------------------------

local NUMBER_VARS = {
	amount = 1.23456789e18,
	dust = 9.87654321e11,
	cost = 1.23456789e18,
	missing = 1.23456789e18,
	glow = 1.23456789e18,
	total = 98765,
	rate = 1.23456789e15,
	n = 9876,
	count = 9876,
	max = 9999,
	points = 98765,
	goal = 99999,
	level = 12,
	stars = 5,
	rank = 12,
	minutes = 59,
	seconds = 59,
	hours = 23,
	day = 7,
	p = 9876,
	chance = 99,
	pct = 99,
	percent = 99,
	price = 1499,
}

function Screens.varsFor(c, key)
	local vars = {}
	local template = (c.Strings[c.lang] and c.Strings[c.lang][key]) or c.Strings.en[key] or ""
	for name in string.gmatch(template, "{(%w+)}") do
		if NUMBER_VARS[name] then
			vars[name] = NUMBER_VARS[name]
		elseif name == "name" then
			vars[name] = Screens.LONG_NAME
		elseif name == "species" then
			vars[name] = "Glimmerwhale"
		elseif name == "time" then
			vars[name] = "59:59"
		elseif name == "weather" then
			vars[name] = if c.lang == "fr" then "Aurore boréale" else "Northern Aurora"
		elseif name == "mult" or name == "bonus" or name == "div" then
			vars[name] = if c.lang == "fr" then "2,36" else "2.36"
		elseif name == "from" or name == "to" then
			vars[name] = 9999
		else
			vars[name] = if c.lang == "fr" then "Étoile filante" else "Shooting Star"
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

-- ---------------------------------------------------------------------------------------------
-- Écrans
-- ---------------------------------------------------------------------------------------------

-- Variantes de l'écran Améliorer : niveaux et Glow (abordable ou non)
local function upgradesState(c, levels, glow, supernovas)
	local data = { upgrades = copy(levels), glow = glow, lastSettle = c.Clock.now(), idleRate = 0 }
	if supernovas then
		data.supernovas = supernovas
	end
	Screens.patch(c, data)
	open(c, "Upgrades")
end

local function money(c, glow, dust)
	Screens.patch(c, { glow = glow, stardust = dust, lastSettle = c.Clock.now() })
end

local BANNER_KINDS = {
	"mythicCatch",
	"legendaryCatch",
	"cometWarn",
	"cometPickup",
	"cometStolen",
	"cometBanked",
	"cometBurst",
	"supernova",
	"megaParade",
	"serverRecord",
	"glowParty",
	"weather",
	"beaconStart",
	"beaconWin",
	"beaconTop",
	"beaconFail",
	"goldenNight",
	"starfall",
	"rookieEnd",
	"atlasMilestone",
	"liveOps",
}

local function bannerScreen(kind)
	return {
		id = "banner." .. kind,
		run = function(c)
			flushBanners(c)
			c.h:fireClient(REMOTES .. "Banner", {
				kind = kind,
				args = {
					name = Screens.LONG_NAME,
					userId = c.players[1].UserId,
					code = codeOf(c, 36, 0, 0),
					s = 23,
					level = 12,
					n = 98765,
					count = 98765,
					minutes = 59,
					key = "aurora",
					form = 1,
					endsAt = c.Clock.now() + 3599,
				},
				priority = 1,
			})
			frames(c, 12)
		end,
	}
end

local CELEBRATIONS = {
	{ "supernova", { level = 12 } },
	{ "atlasNew", { entries = { { s = 23, f = 2 }, { s = 36, f = 0 } } } },
	{ "atlasUnlocked", { count = 5, total = 216 } },
	{ "atlasMilestone", { entries = 150, perches = 10 } },
	{ "speciesComplete", { s = 23 } },
	{ "questDone", { kind = "daily", slot = 2 } },
	{ "questClaimed", { kind = "daily", slot = 2, dust = 9.87654321e11 } },
	{ "dailyClaimed", { day = 7, glow = 1.23456789e18 } },
	{ "starforge", { s = 23, f = 2, stars = 5 } },
	{ "upgrade", { track = "conga", level = 57 } },
	{ "purchase", { key = "GlowCrate" } },
	{ "cometBanked", { glow = 1.23456789e18, dust = 98765 } },
	{ "rookieEnd", {} },
	{ "release", { dust = 9.87654321e11, count = 300 } },
	{ "unlock", { kind = "title", id = "comet_tail" } },
}

local function celebrateScreen(entry)
	return {
		id = "celebrate." .. entry[1],
		run = function(c)
			flushFx(c)
			c.h:fireClient(REMOTES .. "Celebrate", { kind = entry[1], data = entry[2] })
			-- entrée des cartes et du titre (≈ 0,6 s), sans aller jusqu'à leur sortie
			for _ = 1, 8 do
				c.Clock.advance(1 / 10)
				c.h:step(1 / 10, 1)
			end
			c.h:settle(2)
		end,
	}
end

local STAMPS = {
	{ "parade", "PARADE ×2,36 !", "PARADE ×2.36!" },
	{ "snip", "SNIP !", "SNIP!" },
	{ "comet", "COMÈTE VOLÉE !", "COMET STOLEN!" },
	{ "small", "PLEINE !", "FULL!" },
}

-- Groupes d'écrans : un client démarré par groupe (état de données), écrans joués dans l'ordre
function Screens.groups()
	local groups = {}

	-- Écran de chargement (autonome, un harnais par écran : Screens.bootLoading)
	table.insert(groups, {
		id = "loading",
		loading = true,
		screens = {
			{ id = "loading.wake", failed = false },
			{ id = "loading.retry", failed = true },
		},
	})

	-- Nouveau joueur : accueil (étapes 1-7), Améliorer au niveau 0, onglet Accueil des Objectifs
	local newScreens = {
		{
			id = "hud.new",
			run = function(c)
				closeAll(c)
				frames(c, 12)
			end,
		},
	}
	for step = 1, 7 do
		table.insert(newScreens, {
			id = "hud.onboarding.q" .. step,
			run = function(c)
				closeAll(c)
				local data = { onboarding = { step = step, p = 0 } }
				if step >= 2 then
					data.upgrades = { conga = math.min(step, 3), stride = if step >= 5 then 1 else 0, lure = 0, perches = 0, guard = 0 }
					data.stats = { parades = 12, sessions = 1, catches = 40 }
				end
				Screens.patch(c, data)
				frames(c, 60)
			end,
		})
	end
	table.insert(newScreens, {
		id = "upgrades.l0.poor",
		run = function(c)
			Screens.patch(c, { onboarding = { step = 1, p = 0 } })
			upgradesState(c, ZERO_LEVELS, 0)
		end,
	})
	table.insert(newScreens, {
		id = "upgrades.focus",
		run = function(c)
			Screens.patch(c, { glow = 60, lastSettle = c.Clock.now() })
			open(c, "Upgrades", { focus = "conga" })
		end,
	})
	table.insert(newScreens, {
		id = "goals.welcome",
		run = function(c)
			Screens.patch(c, { onboarding = { step = 3, p = 0 } })
			open(c, "Goals", { tab = "welcome" })
		end,
	})
	table.insert(newScreens, {
		id = "collection.perches.empty",
		run = function(c)
			open(c, "Collection", { tab = "perches" })
		end,
	})
	table.insert(groups, { id = "new", state = "new", screens = newScreens })

	-- Milieu de partie : HUD complet, chaque panneau et chaque onglet
	local mid = {
		{
			id = "hud.mid",
			run = function(c)
				closeAll(c)
				frames(c, 10)
			end,
		},
		{
			id = "hud.cheer",
			run = function(c)
				closeAll(c)
				cheer(c)
			end,
		},
		{
			id = "hud.comet",
			run = function(c)
				closeAll(c)
				eventState(c, {
					comet = {
						id = T0 - 10,
						phase = "carried",
						x = 0,
						z = 0,
						code = codeOf(c, 36),
						warnAt = T0 - 30,
						impactAt = T0 - 10,
						burstAt = c.Clock.now() + 45,
						carrierId = c.players[1].UserId,
						carrierSince = c.Clock.now() - 2,
					},
				})
			end,
		},
		{
			id = "hud.beacon",
			run = function(c)
				closeAll(c)
				local now = c.Clock.now()
				eventState(c, {
					beacon = {
						phase = "active",
						warnAt = now - 60,
						startsAt = now - 30,
						endsAt = now + 90,
						points = 98765,
						goal = 99999,
						topUserId = c.players[1].UserId,
					},
				})
			end,
		},
		{
			id = "hud.status",
			run = function(c)
				eventState(c, {})
				Screens.patch(c, { boosts = { personalUntil = c.Clock.now() + 3599 } })
				c.h.localPlayer:SetAttribute("Unstable", true)
				frames(c, 6)
			end,
		},
		{
			id = "hud.minimap",
			run = function(c)
				c.h.localPlayer:SetAttribute("Unstable", nil)
				closeAll(c)
				c.Minimap.setExpanded(true)
				frames(c, 8)
			end,
		},
		{
			id = "upgrades.mid.poor",
			run = function(c)
				c.Minimap.setExpanded(false)
				upgradesState(c, MID_LEVELS, 10)
			end,
		},
		{
			id = "upgrades.mid.afford",
			run = function(c)
				upgradesState(c, MID_LEVELS, 1.23456789e12)
			end,
		},
		{
			id = "upgrades.l0.afford",
			run = function(c)
				upgradesState(c, ZERO_LEVELS, 1.23456789e6)
			end,
		},
		{
			id = "upgrades.mixed",
			run = function(c)
				-- Conga au plafond (R0 : 12), Foulée abordable, Attrait trop cher, Perchoirs au plafond
				upgradesState(c, { conga = 12, stride = 3, lure = 11, perches = 27, guard = 4 }, 5000)
			end,
		},
		{
			id = "supernova.preview",
			run = function(c)
				Screens.patch(c, { upgrades = copy(MID_LEVELS), glow = 1234567, lastSettle = c.Clock.now() })
				goHome(c)
				open(c, "Upgrades")
				c.PC.open("Supernova")
				frames(c, 10)
			end,
		},
		{
			id = "supernova.away",
			run = function(c)
				Screens.patch(c, { glow = 10, lastSettle = c.Clock.now() })
				goAway(c)
				open(c, "Supernova")
			end,
		},
		{
			id = "collection.perches",
			run = function(c)
				goHome(c)
				open(c, "Collection", { tab = "perches" })
			end,
		},
		{
			id = "collection.stash",
			run = function(c)
				open(c, "Collection", { tab = "stash" })
			end,
		},
		{
			id = "collection.stash.select",
			run = function(c)
				open(c, "Collection", { tab = "stash" })
				local Collection = panel(c, "Collection")
				Collection._setSelectMode(true)
				for _, uid in { "u1", "u2", "u3" } do
					Collection._tap(uid)
				end
				frames(c, 6)
			end,
		},
		{
			id = "collection.forge",
			run = function(c)
				local Collection = panel(c, "Collection")
				pcall(Collection._setSelectMode, false)
				open(c, "Collection", { tab = "forge" })
			end,
		},
		{
			id = "collection.atlas",
			run = function(c)
				open(c, "Collection", { tab = "atlas" })
			end,
		},
		{
			id = "collection.guide",
			run = function(c)
				open(c, "Collection", { tab = "guide" })
			end,
		},
		{
			id = "goals.today",
			run = function(c)
				open(c, "Goals", { tab = "today" })
			end,
		},
		{
			id = "goals.calendar",
			run = function(c)
				open(c, "Goals", { tab = "calendar" })
			end,
		},
		{
			id = "goals.week",
			run = function(c)
				open(c, "Goals", { tab = "week" })
			end,
		},
		{
			id = "shop.passes",
			run = function(c)
				open(c, "Shop", { tab = "passes" })
			end,
		},
		{
			id = "shop.boosts",
			run = function(c)
				open(c, "Shop", { tab = "boosts" })
			end,
		},
		{
			id = "shop.codes",
			run = function(c)
				open(c, "Shop", { tab = "codes" })
			end,
		},
		{
			id = "shop.codes.status",
			run = function(c)
				open(c, "Shop", { tab = "codes" })
				local Shop = panel(c, "Shop")
				local box = Shop._codeBox()
				if box then
					box.Text = "LUMORA2026"
					Shop._redeem()
					c.h:settle(2)
				end
				frames(c, 3)
			end,
		},
		{
			id = "crew.solo",
			run = function(c)
				c.WSC.crews = function()
					return { crews = {} }
				end
				open(c, "Crew")
			end,
		},
		{
			id = "crew.members",
			run = function(c)
				local me = c.h.localPlayer.UserId
				local ids = { me, c.players[1].UserId, c.players[4].UserId }
				c.WSC.crews = function()
					return { crews = { { id = 1, userIds = ids } } }
				end
				c.WSC.CrewsChanged:Fire({ crews = { { id = 1, userIds = ids } } })
				open(c, "Crew")
			end,
		},
		{
			id = "crew.invite",
			run = function(c)
				closeAll(c)
				c.WSC.crews = function()
					return { crews = {} }
				end
				c.h:fireClient(
					REMOTES .. "CrewInvitePrompt",
					{ inviterId = c.players[1].UserId, expiresAt = c.Clock.now() + 20 }
				)
				frames(c, 12)
			end,
		},
		{
			id = "settings",
			run = function(c)
				open(c, "Settings")
			end,
		},
		{
			id = "settings.admin",
			run = function(c)
				c.h.localPlayer:SetAttribute("Admin", true)
				open(c, "Settings")
				local scroll = nil
				for _, d in c.h.localPlayer.PlayerGui.Panels:GetDescendants() do
					if d.ClassName == "ScrollingFrame" and Layout.visible(d) then
						scroll = d
					end
				end
				if scroll then
					scroll.CanvasPosition = Vector2.new(0, 100000)
				end
				frames(c, 3)
			end,
		},
		{
			id = "returnscreen",
			run = function(c)
				c.h.localPlayer:SetAttribute("Admin", nil)
				closeAll(c)
				c.h:fireClient(
					REMOTES .. "Celebrate",
					{ kind = "offline", data = { glow = 1.23456789e18, seconds = 43199, nightShift = false } }
				)
				frames(c, 40)
			end,
		},
	}
	table.insert(groups, { id = "mid", state = "mid", screens = mid })

	-- Fin de partie : niveaux au maximum, Supernova XII, réserve pleine, passes possédés
	local late = {
		{
			id = "hud.late",
			run = function(c)
				closeAll(c)
				frames(c, 10)
			end,
		},
		{
			id = "upgrades.max",
			run = function(c)
				open(c, "Upgrades")
			end,
		},
		{
			id = "supernova.late",
			run = function(c)
				goHome(c)
				open(c, "Supernova")
			end,
		},
		{
			id = "collection.perches.full",
			run = function(c)
				open(c, "Collection", { tab = "perches" })
			end,
		},
		{
			id = "collection.stash.full",
			run = function(c)
				open(c, "Collection", { tab = "stash" })
			end,
		},
		{
			id = "collection.forge.full",
			run = function(c)
				open(c, "Collection", { tab = "forge" })
			end,
		},
		{
			id = "collection.atlas.full",
			run = function(c)
				open(c, "Collection", { tab = "atlas" })
			end,
		},
		{
			id = "goals.today.late",
			run = function(c)
				open(c, "Goals", { tab = "today" })
			end,
		},
		{
			id = "goals.week.late",
			run = function(c)
				open(c, "Goals", { tab = "week" })
			end,
		},
		{
			id = "shop.passes.owned",
			run = function(c)
				open(c, "Shop", { tab = "passes" })
			end,
		},
		{
			id = "settings.late",
			run = function(c)
				open(c, "Settings")
			end,
		},
	}
	table.insert(groups, { id = "late", state = "late", screens = late })

	-- Très grands nombres : 1e6, 1e12, 1e18, 1e30 de Glow et de Stardust
	local huge = {}
	for _, e in { 6, 12, 18, 30 } do
		local value = 1.23456789 * 10 ^ e
		table.insert(huge, {
			id = "hud.e" .. e,
			run = function(c)
				closeAll(c)
				money(c, value, value)
				frames(c, 6)
			end,
		})
		table.insert(huge, {
			id = "upgrades.e" .. e,
			run = function(c)
				-- niveaux à mi-chemin (prix visibles), Glow énorme : tout est abordable
				upgradesState(c, MID_LEVELS, value, 40)
			end,
		})
		table.insert(huge, {
			id = "supernova.e" .. e,
			run = function(c)
				goHome(c)
				open(c, "Supernova")
			end,
		})
	end
	table.insert(huge, {
		id = "returnscreen.e30",
		run = function(c)
			closeAll(c)
			c.h:fireClient(
				REMOTES .. "Celebrate",
				{ kind = "offline", data = { glow = 1.23456789e30, seconds = 43199, nightShift = true } }
			)
			frames(c, 40)
		end,
	})
	table.insert(groups, { id = "huge", state = "huge", screens = huge })

	-- Retours passagers : toasts (toutes les clés feedback.*), bannières, célébrations, tampons
	local fx = {}
	table.insert(fx, {
		id = "toasts.stack",
		run = function(c)
			closeAll(c)
			c.Toast.show(c.Prefs.t("feedback.notEnoughGlow", { missing = c.Prefs.number(1.23456789e18) }), "error")
			c.Toast.show(c.Prefs.t("hud.status.boost", { time = "59:59" }), "reward")
			c.Toast.show(c.Prefs.t("common.notEnough", { currency = "Stardust" }), "warning")
			frames(c, 4)
		end,
	})
	table.insert(fx, { id = "feedback.all", feedback = true })
	for _, kind in BANNER_KINDS do
		table.insert(fx, bannerScreen(kind))
	end
	for _, entry in CELEBRATIONS do
		table.insert(fx, celebrateScreen(entry))
	end
	for _, s in STAMPS do
		table.insert(fx, {
			id = "stamp." .. s[1],
			run = function(c)
				flushBanners(c)
				flushFx(c)
				c.FX.stamp(if c.lang == "fr" then s[2] else s[3], Color3.new(1, 1, 1), s[1])
				frames(c, 4)
			end,
		})
	end
	table.insert(fx, {
		id = "floaters",
		run = function(c)
			flushFx(c)
			local w, h = c.profile.w, c.profile.h
			c.FX.floater("+1,23 Qi", Vector2.new(4, h - 4), Color3.new(1, 1, 1))
			c.FX.floater("+98 765 ✦", Vector2.new(w / 2, h / 3), Color3.new(1, 1, 1))
			c.FX.floater("+9,87 T", Vector2.new(w - 4, 4), Color3.new(1, 1, 1))
			frames(c, 2)
		end,
	})
	table.insert(groups, { id = "fx", state = "mid", screens = fx })

	return groups
end

-- Écrans « feedback.N » : chaque clé feedback.* affichée (3 par écran, la pile en garde 3)
function Screens.feedbackScreens(c)
	local out = {}
	local keys = Screens.keysWithPrefix(c, "feedback.")
	local tones = { "error", "success", "reward", "info", "warning" }
	for i = 1, #keys, 3 do
		local batch = { table.unpack(keys, i, math.min(i + 2, #keys)) }
		table.insert(out, {
			id = string.format("feedback.%02d", (i - 1) // 3 + 1),
			keys = batch,
			run = function(cc)
				flushBanners(cc)
				flushFx(cc)
				for j, key in batch do
					cc.h:fireClient(REMOTES .. "Feedback", {
						key = key,
						vars = Screens.varsFor(cc, key),
						tone = tones[(i + j) % #tones + 1],
					})
				end
				frames(cc, 4)
			end,
		})
	end
	return out
end

-- Liste à plat des écrans d'un groupe (les écrans « feedback.all » sont développés)
function Screens.expand(c, group)
	local out = {}
	for _, screen in group.screens do
		if screen.feedback then
			for _, s in Screens.feedbackScreens(c) do
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
	local ok, err = pcall(screen.run, c)
	return ok, if ok then nil else tostring(err)
end

-- ---------------------------------------------------------------------------------------------
-- Mesures
-- ---------------------------------------------------------------------------------------------

Screens.LAYOUT_OPTIONS = { fidelity = true, measureText = TextFit.measureAuto }

function Screens.layout(c)
	Layout.apply(c.h, Screens.LAYOUT_OPTIONS)
end

function Screens.rootScale(c): number
	return c.Root.scale()
end

-- Écran de chargement (src/first/Loading.client, autonome) : harnais sans client ; `failed` :
-- délai dépassé (bouton Réessayer)
function Screens.bootLoading(Harness, profile, lang: string, failed: boolean)
	local MockInstance = require("./MockInstance")
	local h = Harness.new({
		mode = "client",
		console = profile.console == true,
		touch = profile.touch == true,
		viewport = Vector2.new(profile.w, profile.h),
	})
	if profile.display then
		h.game.GuiService.ViewportDisplaySize = Enum.DisplaySize[profile.display]
	end
	h.localPlayer.LocaleId = if lang == "fr" then "fr-fr" else "en-us"
	MockInstance.classMethods.ReplicatedFirst = { RemoveDefaultLoadingScreen = function() end }
	local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
	Clock.freeze(T0)
	h:run("ReplicatedFirst.Loading")
	MockInstance.classMethods.ReplicatedFirst = nil
	local c = { h = h, Clock = Clock, profile = profile, lang = lang, state = "loading", players = {} }
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
			and (Props.get(d, "TextTransparency") or 0) < 0.99
		then
			table.insert(out, d)
		end
	end
	return out
end

local function isKey(c, text)
	return c.Strings.en[text] ~= nil
end

-- Problèmes de texte de l'écran courant (après Screens.layout) :
--   { path, text, kind, message, realSize }
-- kinds : overflow, splitWord, truncated, small (TextFit.fits), rawKey (clé de localisation
-- affichée), placeholder (« {variable} » brute), question (« ? » seul), defaultText (texte jamais
-- posé : « Label » / « Button » du moteur)
function Screens.textIssues(c, opts)
	opts = opts or {}
	local rootScale = Screens.rootScale(c)
	local out = {}
	for _, obj in Screens.visibleTexts(c) do
		local ok, d = TextFit.fits(obj, { rootScale = rootScale })
		local path = Layout.name(obj)
		local function add(kind, message)
			table.insert(out, {
				path = path,
				text = d and d.text or "",
				kind = kind,
				message = message,
				realSize = d and d.realSize or 0,
			})
		end
		if not ok then
			for _, issue in d.issues do
				add(issue.kind, issue.message)
			end
		end
		local text = d and d.text or ""
		local trimmed = string.gsub(string.gsub(text, "^%s+", ""), "%s+$", "")
		if trimmed == "?" then
			add("question", "« ? » affiché au joueur")
		elseif isKey(c, trimmed) then
			add("rawKey", "clé de localisation affichée telle quelle")
		elseif string.find(text, "{%w+}") then
			add("placeholder", "variable non remplacée")
		end
		if not Props.written(obj, "Text") and obj.ClassName ~= "TextBox" then
			add("defaultText", "texte jamais posé : le moteur affiche « " .. tostring(Props.get(obj, "Text")) .. " »")
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

return Screens
