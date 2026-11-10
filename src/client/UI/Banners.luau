--!strict
-- Banners (paquet client-hud, docs/04 §10.4, §13.5) : bannières (GDD §6.6, §9.4) dans l'emplacement
-- de message du HUD (Layout.Hud.message : 1000 × 112 px TV, titre 48 px, ligne 32 px).
--   * Bannières de serveur (remote Banner, file de CommunityService ou Notify.personalBanner) et
--     bannières d'événement calculées par le client avec Logic/EventClock (sirène et début du BOOP
--     RUSH, alerte MEGA avec compte à rebours, début de la Jelly Moon), SEULEMENT si l'interrupteur du
--     serveur est vrai (WorldStateController.event().features ; jamais Config/Features) ; une bannière
--     d'événement par créneau (index), jamais rejouée.
--   * Une seule bannière à l'écran, Events.Banners.Duration (3 s), par priorité (1 = plus haute ;
--     événements d'abord), 3 au plus en attente ; les messages (Toast) attendent pendant une bannière
--     (Hud/Messages.hold).
--   * Nouveau avant l'étape 9 de l'accueil (setQuiet, OnboardingController) : aucune bannière
--     d'événement ; les bannières des autres sont retenues puis jetées après Events.Banners.StaleAfter
--     (30 s) ; les siennes et les personnelles passent.
-- Juice : apparition 0,85 → 1 (Back Out) et sortie 0,15 s, fondus en Mouvement réduit. Temps : Clock.
-- v2.0 (lot B3, étape 5, D20 ; GDD v2.0 §4.27, §6.6 ; notes du lot A2) :
--   * « banner.ascend » (Jelly Ascend d'un joueur, sorte « ascend » du serveur) passe comme les autres ;
--   * Pluie d'étoiles : le héros du Celebrate « ascend » en cours est retenu jusqu'à son endsAt + 5 s ; un
--     Celebrate « giftRain » dont heroId est ce héros (cadeaux de son Ascension) donne le message
--     « Pluie d'étoiles ! » (Hud/Messages), une fois ;
--   * petite ligne (le serveur ne montre qu'une bannière de Grand Splorch toutes les 3 min par joueur
--     avec la progression v2.0) : interrupteur RecordR ouvert, un Celebrate « splorch » d'un AUTRE joueur
--     sans sa bannière « splorch » à burstAt + 1,5 s donne le texte de « banner.splorch » en message ;
--     jamais pendant le mode discret du nouveau ; une bannière de ce joueur arrivée en retard après la
--     ligne est jetée (jamais les deux). Interrupteurs coupés : rien de tout cela (aucune ligne).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Clock = require(Shared.Util.Clock)
local Layout = require(Shared.Config.Layout)
local Events = require(Shared.Config.Events)
local EventClock = require(Shared.Logic.EventClock)
local BigNumber = require(Shared.Logic.BigNumber)
local WorldLayout = require(Shared.Logic.WorldLayout)

local Client = script.Parent.Parent
local Root = require(Client.UI.Root)
local Theme = require(Client.UI.Theme)
local Juice = require(Client.UI.Juice)
local Text = require(Client.UI.Text)
local Prefs = require(Client.Util.Prefs)
local AudioController = require(Client.Controllers.AudioController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local HUD = require(Client.UI.HUD)
local Util = require(Client.UI.Hud.Util)
local Messages = require(Client.UI.Hud.Messages)
local MetaFlags = require(Client.UI.MetaFlags)

local Banners = {}

local CFG = Events.Banners
local SLOT = Layout.Hud.message
local CONTENT = Layout.HudContent.message
local EVENT_PRIORITY = 0 -- bannières d'événement : avant celles des joueurs
local EVENT_WINDOW = 6 -- s : une bannière d'événement manquée de plus de 6 s n'est plus montrée
-- Son de chaque bannière d'événement (GDD §9.4, §9.6) ; jamais pour un nouveau avant l'étape 9
local EVENT_SOUNDS: { [string]: string } = {
	rushSoon = "RushSiren",
	megaWarn = "MegaWarn",
	moonStart = "MoonStart",
}
local CHECK_EVERY = 0.25 -- s entre deux calculs des bannières d'événement
-- v2.0 (lot B3, D20) : Pluie d'étoiles et petite ligne du Grand Splorch
local STAR_RAIN_GRACE = 5 -- s après endsAt du Celebrate « ascend » : héros encore retenu
local LINE_DELAY = 1.5 -- s après burstAt : sans bannière « splorch » de ce joueur, la petite ligne
local LINE_LATE = 20 -- s : une bannière de ce joueur arrivée après sa ligne est jetée pendant ce temps
local LINE_MAX = 16 -- Grands Splorch suivis au plus (un par joueur du serveur)
local WINDOW_S = 120 -- s : heure d'une charge plus loin que cela de Clock.now() : charge ignorée

local ACCENTS: { [string]: Color3 } = {
	rushSoon = Color3.fromRGB(255, 150, 210),
	rushStart = Color3.fromRGB(255, 150, 210),
	megaWarn = Color3.fromRGB(255, 208, 72),
	moonStart = Color3.fromRGB(170, 130, 255),
	splorch = Color3.fromRGB(255, 208, 72),
	wobbleParty = Color3.fromRGB(255, 170, 90),
	squishParty = Color3.fromRGB(255, 170, 90),
	squishPartyBy = Color3.fromRGB(255, 170, 90),
	adminParty = Color3.fromRGB(255, 170, 90),
}

type Entry = {
	kind: string,
	title: string,
	line: string,
	lineUntil: number, -- compte à rebours de la ligne (Clock.now() de fin ; 0 = aucun)
	priority: number,
	at: number, -- arrivée (Clock.now())
	others: boolean, -- bannière d'un autre joueur (retenue pour un nouveau)
	seq: number,
}

local queue: { Entry } = {}
local current: Entry? = nil
local currentUntil = 0
local quiet = false
local photo = false -- mode photo (vignettes) : aucune bannière à l'écran, la file attend
local seq = 0
local started = false
local frame: Frame? = nil
local titleLabel: TextLabel? = nil
local lineLabel: TextLabel? = nil
local accentBar: Frame? = nil
local shownEvents: { [string]: number } = {} -- sorte d'événement → dernier index montré
local checkAcc = 0
-- v2.0 (D20) : héros de la Jelly Ascend en cours ; Grands Splorch des autres en attente de leur bannière
-- (userId → heure de la petite ligne) ; petites lignes montrées (userId → heure)
local ascendHero: { userId: number, untilT: number }? = nil
local pendingLines: { [number]: number } = {}
local pendingCount = 0
local linesShown: { [number]: number } = {}

-- =============================================================================================
-- Construction
-- =============================================================================================

local function container(): Instance?
	local slot = Util.safe("HUD.element", nil, HUD.element, "message")
	if slot ~= nil then
		return slot
	end
	-- repli : écran propre au rectangle de l'emplacement de message
	local ok, safe = pcall(Root.safe, "Banners", 12)
	if not ok then
		return nil
	end
	local holder = safe:FindFirstChild("MessageSlot")
	if holder == nil then
		local f = Instance.new("Frame")
		f.Name = "MessageSlot"
		f.BackgroundTransparency = 1
		Util.place(f, SLOT)
		f.Parent = safe
		holder = f
	end
	return holder
end

local function build()
	if frame ~= nil and frame.Parent ~= nil then
		return
	end
	local parent = container()
	if parent == nil then
		return
	end
	local f = Instance.new("Frame")
	f.Name = "Banner"
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Position = UDim2.fromScale(0.5, 0)
	f.Size = UDim2.fromOffset(SLOT.rect.w, SLOT.rect.h)
	f.BackgroundColor3 = Theme.Colors.Panel
	f.BackgroundTransparency = 0.08
	f.Visible = false
	f.Active = false
	f.ZIndex = 20
	Util.chrome(f, Layout.Corner.Max)
	local bar = Instance.new("Frame")
	bar.Name = "Accent"
	bar.Size = UDim2.new(1, -24, 0, 6)
	bar.Position = UDim2.fromOffset(12, 6)
	bar.BackgroundColor3 = Theme.Colors.Gold
	bar.BorderSizePixel = 0
	bar.ZIndex = 21
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0.5, 0)
	bc.Parent = bar
	bar.Parent = f
	titleLabel = Util.label({
		name = "Title",
		parent = f,
		size = UDim2.new(1, -48, 0, 60),
		position = UDim2.fromOffset(24, 12),
		textSize = CONTENT.bannerTitle,
		font = Font.fromEnum(Enum.Font.LuckiestGuy),
		zIndex = 22,
		-- titre de longueur libre (nom d'un joueur de 20 caractères, espèce, mutation) : plus grande
		-- taille qui tient sur la ligne, comme l'ancien TextScaled (UI/Text, sorte "fit")
		fit = true,
	})
	lineLabel = Util.label({
		name = "Line",
		parent = f,
		size = UDim2.new(1, -48, 0, 36),
		position = UDim2.fromOffset(24, 72),
		textSize = CONTENT.bannerLine,
		font = Theme.Fonts.Title,
		color = Theme.Colors.TextDim,
		zIndex = 22,
	})
	f.Parent = parent
	frame = f
	accentBar = bar
end

-- =============================================================================================
-- File
-- =============================================================================================

local function localUserId(): number
	local player = Players.LocalPlayer
	return if player then player.UserId else 0
end

local function sortQueue()
	table.sort(queue, function(a, b)
		if a.priority ~= b.priority then
			return a.priority < b.priority
		end
		return a.seq < b.seq
	end)
end

local function enqueue(entry: Entry)
	seq += 1
	entry.seq = seq
	table.insert(queue, entry)
	sortQueue()
	-- 3 au plus en attente : la moins prioritaire (la plus récente à égalité) est jetée
	while #queue > CFG.QueueMax do
		table.remove(queue)
	end
end

local function hideCurrent()
	local f = frame
	current = nil
	Messages.hold("banner", false)
	if f and f.Visible then
		if Prefs.reducedMotion() then
			f.Visible = false
		else
			Juice.popOut(f)
		end
	end
end

local function showEntry(entry: Entry, now: number)
	build()
	local f = frame
	if f == nil then
		return
	end
	current = entry
	currentUntil = now + CFG.Duration
	Messages.hold("banner", true)
	local title = titleLabel :: TextLabel
	local line = lineLabel :: TextLabel
	Text.raw(title, entry.title)
	Text.raw(line, if entry.lineUntil > 0 then Util.clock(entry.lineUntil - now) else entry.line)
	line.Visible = entry.line ~= "" or entry.lineUntil > 0
	if accentBar then
		accentBar.BackgroundColor3 = ACCENTS[entry.kind] or Theme.Colors.Gold
	end
	f:SetAttribute("BannerKind", entry.kind)
	if Prefs.reducedMotion() then
		f.Visible = true
		Juice.scaleOf(f).Scale = 1
	else
		Juice.popIn(f)
	end
end

-- Nom affiché d'un joueur pour la petite ligne : celui de son ranch (alias s'il le cache)
local function playerName(userId: number): string
	for slot = 1, WorldLayout.Const.Ranches do
		local r = Util.safe("WorldStateController.ranch", nil, WorldStateController.ranch, slot)
		if type(r) == "table" and r.userId == userId then
			return Util.displayName(userId, r.name)
		end
	end
	return Util.displayName(userId, "")
end

-- Lignes montrées oubliées après LINE_LATE (borne mémoire : un joueur du serveur au plus chacun)
local function pruneShown(now: number)
	for userId, at in linesShown do
		if now - at > LINE_LATE or now < at then
			linesShown[userId] = nil
		end
	end
end

-- Petites lignes dues (v2.0, D20) : seulement si RecordR est toujours ouvert et hors mode discret
local function stepLines(now: number)
	pruneShown(now)
	for userId, due in pendingLines do
		if now >= due or now < due - WINDOW_S then
			pendingLines[userId] = nil
			pendingCount -= 1
			if now >= due and now - due <= LINE_LATE and not quiet and MetaFlags.on("RecordR") then
				linesShown[userId] = now
				Messages.push(Prefs.t("banner.splorch", { name = playerName(userId) }), "info")
			end
		end
	end
end

local function step(now: number)
	if pendingCount > 0 then
		stepLines(now)
	end
	-- bannières des autres retenues pour un nouveau : jetées après StaleAfter
	for i = #queue, 1, -1 do
		local e = queue[i]
		local age = now - e.at
		if age > CFG.StaleAfter or age < -CFG.StaleAfter then
			table.remove(queue, i)
		end
	end
	if photo then
		if current ~= nil then
			hideCurrent()
		end
		return
	end
	local cur = current
	if cur ~= nil then
		if cur.lineUntil > 0 and lineLabel then
			Text.raw(lineLabel, Util.clock(cur.lineUntil - now))
		end
		if now >= currentUntil or now < currentUntil - CFG.Duration - 1 then
			hideCurrent()
		else
			return
		end
	end
	for i, e in queue do
		if not (quiet and e.others) then
			table.remove(queue, i)
			showEntry(e, now)
			return
		end
	end
end

-- =============================================================================================
-- Bannières d'événement (EventClock + interrupteurs du serveur)
-- =============================================================================================

local function features(): Types.EventFeatures?
	local ev = Util.safe("WorldStateController.event", nil, WorldStateController.event)
	if type(ev) ~= "table" or type(ev.features) ~= "table" then
		return nil
	end
	return ev.features
end

local function eventBanner(kind: string, index: number, at: number, now: number, lineUntil: number)
	if shownEvents[kind] == index then
		return
	end
	if now < at or now > at + EVENT_WINDOW then
		return
	end
	shownEvents[kind] = index
	if quiet then
		return -- nouveau avant l'étape 9 : aucune bannière d'événement
	end
	local sound = EVENT_SOUNDS[kind]
	if sound then
		Util.safe("AudioController.play", nil, AudioController.play, sound)
	end
	local key = "banner." .. kind
	if not Util.has(key) then
		return
	end
	enqueue({
		kind = kind,
		title = Prefs.t(key),
		line = "",
		lineUntil = lineUntil,
		priority = EVENT_PRIORITY,
		at = now,
		others = false,
		seq = 0,
	})
end

-- BOOP RUSH programmé visible : mode « on », ou mode « events » pendant la Jelly Moon ou une fête
-- d'administrateur (même règle que RushService côté serveur et LightingController pour le ciel)
local function rushAllowed(f: any, now: number): boolean
	if f.boopRush == "on" then
		return true
	end
	if f.boopRush ~= "events" then
		return false
	end
	local ev: any = Util.safe("WorldStateController.event", nil, WorldStateController.event)
	if type(ev) ~= "table" then
		return false
	end
	if f.jellyMoon == true then
		local m: any = ev.moon
		if type(m) == "table" and m.active == true and type(m.endsAt) == "number" and now < m.endsAt then
			return true
		end
		if EventClock.moon(now).active then
			return true
		end
	end
	local b: any = ev.boost
	return type(b) == "table" and b.kind == "admin" and type(b.untilT) == "number" and now < b.untilT
end

local function checkEvents(now: number)
	local f = features()
	if f == nil then
		return
	end
	if rushAllowed(f, now) then
		local rush = EventClock.rush(now)
		eventBanner("rushSoon", rush.index, rush.sirenAt, now, 0)
		eventBanner("rushStart", rush.index, rush.startsAt, now, 0)
	end
	if f.megaSquish == true then
		local mega = EventClock.mega(now)
		eventBanner("megaWarn", mega.index, mega.warnAt, now, mega.landsAt)
	end
	if f.jellyMoon == true then
		local moon = EventClock.moon(now)
		-- numéro de séance unique dans le temps : début de la séance
		eventBanner("moonStart", math.floor(moon.startsAt), moon.startsAt, now, 0)
	end
end

-- =============================================================================================
-- Bannières de serveur
-- =============================================================================================

-- Texte d'une bannière de serveur, ou nil si la sorte est inconnue (rien n'est affiché)
local function serverText(kind: string, args: { [string]: any }): string?
	local key = "banner." .. kind
	if not Util.has(key) then
		return nil
	end
	local vars = Util.vars(args)
	-- « Premier à 1 MILLIARD » : mot entier du jalon
	local word: string? = nil
	if type(args.word) == "string" and Util.has(args.word) then
		word = Prefs.t(args.word)
	else
		local n = if type(args.threshold) == "number" then args.threshold else args.n
		if type(n) == "number" then
			local wordKey = BigNumber.milestoneKey(n)
			if wordKey and Util.has(wordKey) then
				word = Prefs.t(wordKey)
			end
		end
	end
	if word then
		vars.word = word
	end
	return Prefs.t(key, vars)
end

local function onBanner(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local kind = Util.str(payload.kind, "", 40)
	if kind == "" then
		return
	end
	local args = Util.tbl(payload.args)
	local text = serverText(kind, args)
	if text == nil then
		return
	end
	local fromId = Util.num(args.userId, 0, 0, 2 ^ 53)
	if kind == "splorch" and fromId > 0 then
		-- v2.0 (D20) : sa bannière est arrivée, aucune petite ligne ; arrivée en retard après la ligne :
		-- jetée (le joueur a déjà vu la nouvelle)
		if pendingLines[fromId] ~= nil then
			pendingLines[fromId] = nil
			pendingCount -= 1
		end
		local shownAt = linesShown[fromId]
		if shownAt ~= nil then
			linesShown[fromId] = nil
			local age = Clock.now() - shownAt
			if age >= 0 and age <= LINE_LATE then
				return
			end
		end
	end
	local personal = payload.personal == true
	enqueue({
		kind = kind,
		title = text,
		line = "",
		lineUntil = 0,
		priority = Util.num(payload.priority, CFG.QueueMax + 4, 1, 99),
		at = Clock.now(),
		others = not personal and fromId ~= localUserId(),
		seq = 0,
	})
	step(Clock.now())
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Création des remotes et des états ; aucun yield long
function Banners.Init()
	table.clear(queue)
	current = nil
end

-- Connexions et boucles
function Banners.Start()
	if started then
		return
	end
	started = true
	build()
	Net.event("Banner").OnClientEvent:Connect(onBanner)
	Net.event("Celebrate").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" or type(payload.data) ~= "table" then
			return
		end
		local kind = payload.kind
		if kind == "photo" then
			photo = payload.data.on == true
			step(Clock.now())
		elseif kind == "ascend" or kind == "giftRain" or kind == "splorch" then
			Banners._onCelebrateV2(kind, payload.data)
		end
	end)
	RunService.Heartbeat:Connect(function(dt: number)
		local now = Clock.now()
		checkAcc += Util.num(dt, 0, 0, 1)
		if checkAcc >= CHECK_EVERY then
			checkAcc = 0
			checkEvents(now)
		end
		step(now)
	end)
	Prefs.LanguageChanged:Connect(function()
		-- textes déjà traduits : la bannière en cours garde sa langue (3 s au plus)
	end)
end

-- Heure d'une charge (Clock.now() du serveur) plausible, sinon nil
local function timeOf(v: any, now: number): number?
	if type(v) ~= "number" or v ~= v or math.abs(v - now) > WINDOW_S then
		return nil
	end
	return v
end

-- v2.0 (D20) : Celebrate « ascend » (héros retenu), « giftRain » (Pluie d'étoiles de ce héros) et
-- « splorch » d'un autre joueur (petite ligne si sa bannière ne vient pas) ; charge vérifiée, rien
-- avec les interrupteurs coupés
function Banners._onCelebrateV2(kind: string, d: { [string]: any })
	local now = Clock.now()
	if kind == "ascend" then
		local userId = Util.num(d.userId, 0, 0, 2 ^ 53)
		local endsAt = timeOf(d.endsAt, now)
		if userId > 0 and userId % 1 == 0 and endsAt ~= nil and MetaFlags.on("JellyAscend") then
			ascendHero = { userId = userId, untilT = endsAt + STAR_RAIN_GRACE }
		end
	elseif kind == "giftRain" then
		local hero = ascendHero
		if hero == nil then
			return
		end
		if now > hero.untilT then
			ascendHero = nil
			return
		end
		if d.heroId == hero.userId then
			ascendHero = nil -- une Pluie d'étoiles par Ascension
			Messages.push(Prefs.t("ascend.starRain"), "reward")
		end
	elseif kind == "splorch" then
		local userId = Util.num(d.userId, 0, 0, 2 ^ 53)
		local burstAt = timeOf(d.burstAt, now)
		if
			userId <= 0
			or userId % 1 ~= 0
			or userId == localUserId()
			or burstAt == nil
			or quiet
			or not MetaFlags.on("RecordR")
		then
			return
		end
		if pendingLines[userId] == nil then
			if pendingCount >= LINE_MAX then
				return
			end
			pendingCount += 1
		end
		pendingLines[userId] = burstAt + LINE_DELAY
		linesShown[userId] = nil
	end
end

-- Met une bannière dans la file (charge utile de serveur, validée comme si elle venait du réseau)
function Banners.show(payload: Types.BannerPayload)
	onBanner(payload)
end

-- Mode discret du nouveau
function Banners.setQuiet(on: boolean)
	quiet = on == true
	if not quiet then
		step(Clock.now())
	end
end

-- Bannières en attente (specs)
function Banners.queued(): number
	return #queue
end

-- Bannière affichée (specs) : sorte et texte
function Banners.current(): { kind: string, title: string }?
	local cur = current
	if cur == nil then
		return nil
	end
	return { kind = cur.kind, title = cur.title }
end

-- Petites lignes en attente (specs : borne mémoire)
function Banners._pendingLines(): number
	return pendingCount
end

-- Un tour tout de suite (specs ; la boucle par image fait de même)
function Banners._step()
	checkEvents(Clock.now())
	step(Clock.now())
end

return Banners
