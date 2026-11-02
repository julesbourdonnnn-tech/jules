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

local Client = script.Parent.Parent
local Root = require(Client.UI.Root)
local Theme = require(Client.UI.Theme)
local Juice = require(Client.UI.Juice)
local Prefs = require(Client.Util.Prefs)
local AudioController = require(Client.Controllers.AudioController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local HUD = require(Client.UI.HUD)
local Util = require(Client.UI.Hud.Util)
local Messages = require(Client.UI.Hud.Messages)

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
	title.Text = entry.title
	line.Text = if entry.lineUntil > 0 then Util.clock(entry.lineUntil - now) else entry.line
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

local function step(now: number)
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
			lineLabel.Text = Util.clock(cur.lineUntil - now)
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

local function checkEvents(now: number)
	local f = features()
	if f == nil then
		return
	end
	if f.boopRush == "on" then
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
		if type(payload) == "table" and payload.kind == "photo" and type(payload.data) == "table" then
			photo = payload.data.on == true
			step(Clock.now())
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

-- Un tour tout de suite (specs ; la boucle par image fait de même)
function Banners._step()
	checkEvents(Clock.now())
	step(Clock.now())
end

return Banners
