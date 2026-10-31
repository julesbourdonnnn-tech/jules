--!strict
-- Banners — paquet « client-hud » (docs/04-architecture.md §13.10).
-- Propriétaire côté client du remote Banner. Affichage en haut au centre (640 × 72, sous la pastille
-- d'événement) : glisse en 0,25 s (Back Out), reste 3 s ; file locale de 3 au plus, triée par
-- priorité (payload.priority, 1 = plus haute) ; bannières personnelles (payload.personal)
-- prioritaires. Une bannière en cours n'est jamais interrompue.
-- Textes : "banner.<kind>" interpolés avec args (noms, niveaux en chiffres romains pour la
-- Supernova, durées restantes, espèces via Config/Nebbies, météo et multiplicateur de forme) ;
-- le texte affiché est recalculé à chaque image (compte à rebours, changement de langue).
-- Sons : BeaconStart, BeaconWin, Whoosh (météo, Starfall, boosts), Pop (exploits), Reward
-- (personnelles) ; les sons déjà joués par VFXController (CometWarn, Supernova, Comète encaissée)
-- ne sont pas doublés.
-- Mouvement réduit : fondu au lieu de la glissade.
-- GDD : §6.5, §9.4 (bannières), §10.2.
-- Dépendances : AudioController, Util/Prefs, UI/Root, UI/Theme, UI/Create, UI/Juice, Shared/Net,
-- Config/Nebbies.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Format = require(Shared.Util.Format)
local Nebbies = require(Shared.Config.Nebbies)
local Events = require(Shared.Config.Events)
local Cosmetics = require(Shared.Config.Cosmetics)

local Client = script.Parent.Parent
local AudioController = require(Client.Controllers.AudioController)
local Prefs = require(Client.Util.Prefs)
local Root = require(Client.UI.Root)
local Theme = require(Client.UI.Theme)
local Create = require(Client.UI.Create)
local Juice = require(Client.UI.Juice)
local WorldStateController = require(Client.Controllers.WorldStateController)
local Text = require(Client.UI.Hud.Text)
local Widgets = require(Client.UI.Hud.Widgets)
local EventPill = require(Client.UI.Hud.EventPill)

local Banners = {}

-- Bannière effectivement affichée
Banners.Shown = Signal.new() :: Signal.Signal<Types.BannerPayload>

-- Constantes (GDD §6.5, §10.2) --------------------------------------------------------------------

local QUEUE_MAX = 3
local HOLD = 3 -- s
local SLIDE_IN = 0.25
local SLIDE_OUT = 0.2
local DISPLAY_ORDER = 40
local TOP_Y = 72 -- sous la pastille d'événement (16 + 48 + 8)
local BEACON_BAR_SPACE = 34 -- barre de serveur de la Balise (28 + 6) affichée sous la pastille
local HIDDEN_Y = -90
local DEFAULT_PRIORITY = 7
local MAX_PRIORITY = 10

local KINDS: { [string]: { color: Color3, sound: string?, icon: string } } = {
	mythicCatch = { color = Nebbies.Rarities[6].color, sound = "Pop", icon = "★" },
	legendaryCatch = { color = Nebbies.Rarities[5].color, sound = "Pop", icon = "★" },
	cometWarn = { color = Color3.fromRGB(255, 205, 60), icon = "☄" },
	cometPickup = { color = Color3.fromRGB(255, 205, 60), icon = "☄" },
	cometStolen = { color = Color3.fromRGB(255, 150, 60), icon = "☄" },
	cometBanked = { color = Color3.fromRGB(255, 205, 60), icon = "☄" },
	cometBurst = { color = Color3.fromRGB(190, 110, 255), icon = "☄" },
	supernova = { color = Color3.fromRGB(255, 245, 220), icon = "✺" },
	megaParade = { color = Theme.Colors.Gold, sound = "Pop", icon = "♛" },
	serverRecord = { color = Theme.Colors.Gold, sound = "Pop", icon = "♛" },
	glowParty = { color = Theme.Colors.Gold, sound = "Whoosh", icon = "✦" },
	weather = { color = Color3.fromRGB(150, 220, 255), sound = "Whoosh", icon = "☁" },
	beaconStart = { color = Color3.fromRGB(90, 230, 255), sound = "BeaconStart", icon = "✧" },
	beaconWin = { color = Color3.fromRGB(255, 120, 190), sound = "BeaconWin", icon = "✧" },
	beaconTop = { color = Color3.fromRGB(90, 230, 255), sound = "Pop", icon = "✧" },
	beaconFail = { color = Color3.fromRGB(130, 150, 210), icon = "✧" },
	goldenNight = { color = Theme.Colors.Gold, sound = "Whoosh", icon = "☾" },
	starfall = { color = Color3.fromRGB(255, 170, 240), sound = "Whoosh", icon = "★" },
	rookieEnd = { color = Cosmetics.Readability.Rookie, sound = "Reward", icon = "◈" },
	atlasMilestone = { color = Theme.Colors.Premium, icon = "❖" },
	liveOps = { color = Theme.Colors.Primary, sound = "Whoosh", icon = "✦" },
}

-- État --------------------------------------------------------------------------------------------

type Entry = { payload: Types.BannerPayload, seq: number }

local started = false
local queue: { Entry } = {}
local seq = 0
local current: Entry? = nil
local showUntil = 0
local hideStarted = false
local frame: CanvasGroup? = nil
local textLabel: TextLabel? = nil
local iconLabel: TextLabel? = nil
local stroke: UIStroke? = nil
local lastText = ""

-- Outils ------------------------------------------------------------------------------------------

local function isFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function ensureGui(): CanvasGroup
	if frame and frame.Parent then
		return frame :: CanvasGroup
	end
	local safe = Root.safe("Banners", DISPLAY_ORDER)
	local label = Widgets.label({
		name = "Text",
		size = UDim2.new(1, -96, 1, -16),
		position = UDim2.fromOffset(76, 8),
		maxSize = 30,
		zIndex = 3,
		strokeThickness = 2,
	})
	label.TextXAlignment = Enum.TextXAlignment.Left
	local icon = Widgets.label({
		name = "Icon",
		size = UDim2.fromOffset(52, 52),
		position = UDim2.new(0, 14, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		maxSize = 44,
		zIndex = 3,
		strokeThickness = 2,
	})
	icon.AutoLocalize = false
	local border = Widgets.stroke(Theme.Colors.Gold, 3)
	local banner = Create("CanvasGroup", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, HIDDEN_Y),
		Size = UDim2.fromOffset(640, 72),
		BackgroundColor3 = Theme.Colors.Background,
		BackgroundTransparency = 0.05,
		GroupTransparency = 1,
		Visible = false,
		Parent = safe,
	}, {
		Widgets.corner(UDim.new(0, 16)),
		border,
		Widgets.gradient(Color3.new(1, 1, 1), Color3.fromRGB(170, 160, 210)),
		label,
		icon,
	})
	frame = banner
	textLabel = label
	iconLabel = icon
	stroke = border
	return banner
end

-- Texte d'une bannière (pur vis-à-vis de l'interface : Prefs.t, Clock)
function Banners.text(payload: Types.BannerPayload): string
	local args = if type(payload.args) == "table" then payload.args else {}
	local kind = payload.kind
	local now = Clock.now()
	local lang = Prefs.language()
	-- valeurs de repli : jamais de « {variable} » brute à l'écran
	local vars: { [string]: any } =
		{ level = "?", n = "?", count = "?", minutes = "?", time = Format.clock(0) }
	vars.name = Text.cleanName(args.name) or "?"
	if isFinite(args.level) then
		vars.level = Text.roman(args.level)
	end
	if isFinite(args.n) then
		vars.n = Prefs.number(math.floor(args.n))
	end
	if isFinite(args.count) then
		vars.count = Prefs.number(math.floor(args.count))
	end
	if isFinite(args.minutes) then
		vars.minutes = math.floor(args.minutes)
	end
	vars.species = Text.speciesName(args.code)
		or (if isFinite(args.s) and Nebbies.Species[args.s] then Nebbies.Species[args.s].name else nil)
		or Text.cleanName(args.species)
		or "?"
	if isFinite(args.endsAt) then
		vars.time = Format.clock(math.max(0, math.ceil(args.endsAt - now)))
	end
	local key = "banner." .. kind
	if kind == "weather" then
		local weatherKey = if type(args.key) == "string" and Events.WeatherByKey[args.key]
			then args.key
			else nil
		vars.weather = if weatherKey then Prefs.t("weather." .. weatherKey) else "?"
		local form = if isFinite(args.form) then Nebbies.Forms[math.floor(args.form)] else nil
		vars.mult = Text.mult(if form then form.mult else 1, lang)
		if weatherKey == "meteor" or form == nil then
			key = "banner.weatherMeteor"
		end
	end
	return Prefs.t(key, vars)
end

-- File : personnelles d'abord, puis priorité croissante, puis ordre d'arrivée
local function sortQueue()
	table.sort(queue, function(a: Entry, b: Entry): boolean
		local pa = if a.payload.personal then 0 else 1
		local pb = if b.payload.personal then 0 else 1
		if pa ~= pb then
			return pa < pb
		end
		if a.payload.priority ~= b.payload.priority then
			return a.payload.priority < b.payload.priority
		end
		return a.seq < b.seq
	end)
end

local function render(entry: Entry)
	ensureGui()
	local def = KINDS[entry.payload.kind]
	local text = Banners.text(entry.payload)
	local label = textLabel :: TextLabel
	if text ~= lastText then
		lastText = text
		label.Text = text
	end
	label.TextColor3 = Widgets.lighten(def.color, 0.35)
	local icon = iconLabel :: TextLabel
	icon.Text = def.icon
	icon.TextColor3 = def.color
	local border = stroke :: UIStroke
	border.Color = def.color
end

-- Hauteur d'affichage : sous la pastille, et sous la barre de la Balise quand le HUD la montre
-- (même règle que la pastille : Hud/EventPill) — sinon la bannière « NUIT DE LA BALISE » cache
-- la barre au moment même où elle apparaît
local function topY(now: number): number
	local ok, state = pcall(
		EventPill.compute,
		WorldStateController.events(),
		now,
		Prefs.t,
		function(_: number)
			return nil
		end
	)
	if ok and state and state.bar ~= nil then
		return TOP_Y + BEACON_BAR_SPACE
	end
	return TOP_Y
end

local function present(entry: Entry)
	local banner = ensureGui()
	current = entry
	hideStarted = false
	lastText = ""
	local now = Clock.now()
	showUntil = now + SLIDE_IN + HOLD
	render(entry)
	banner.Visible = true
	local target = UDim2.new(0.5, 0, 0, topY(now))
	if Prefs.reducedMotion() then
		banner.Position = target
		banner.GroupTransparency = 1
		Juice.tween(banner, SLIDE_IN, { GroupTransparency = 0 })
	else
		banner.Position = UDim2.new(0.5, 0, 0, HIDDEN_Y)
		banner.GroupTransparency = 0
		Juice.tween(banner, SLIDE_IN, { Position = target }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
	local def = KINDS[entry.payload.kind]
	local sound = if entry.payload.personal then "Reward" else def.sound
	if sound then
		AudioController.play(sound)
	end
	Banners.Shown:Fire(entry.payload)
end

local function finish()
	current = nil
	local banner = frame
	if banner then
		banner.Visible = false
	end
	local nextEntry = table.remove(queue, 1)
	if nextEntry then
		present(nextEntry)
	end
end

local function onFrame()
	local entry = current
	if entry == nil then
		if #queue > 0 then
			present(table.remove(queue, 1) :: Entry)
		end
		return
	end
	local now = Clock.now()
	render(entry)
	if not hideStarted and now >= showUntil then
		hideStarted = true
		local banner = frame
		if banner then
			if Prefs.reducedMotion() then
				Juice.tween(banner, SLIDE_OUT, { GroupTransparency = 1 })
			else
				Juice.tween(
					banner,
					SLIDE_OUT,
					{ Position = UDim2.new(0.5, 0, 0, HIDDEN_Y), GroupTransparency = 1 },
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In
				)
			end
		end
	elseif hideStarted and now >= showUntil + SLIDE_OUT then
		finish()
	end
end

-- Normalise une charge reçue (nil si invalide : ignorée sans erreur)
local function normalize(payload: any): Types.BannerPayload?
	if type(payload) ~= "table" or type(payload.kind) ~= "string" or KINDS[payload.kind] == nil then
		return nil
	end
	local priority = payload.priority
	if not isFinite(priority) or priority < 1 or priority > MAX_PRIORITY then
		priority = DEFAULT_PRIORITY
	end
	local args: { [string]: any } = {}
	if type(payload.args) == "table" then
		local count = 0
		for k, v in payload.args do
			if
				type(k) == "string"
				and #k <= 24
				and (type(v) == "string" or type(v) == "number" or type(v) == "boolean")
			then
				args[k] = v
				count += 1
				if count >= 16 then
					break
				end
			end
		end
	end
	return {
		kind = payload.kind :: Types.BannerKind,
		args = args,
		priority = math.floor(priority),
		personal = payload.personal == true,
	}
end

-- API -------------------------------------------------------------------------------------------

-- Met une bannière en file (utilisé par le remote et par les modules locaux)
function Banners.show(payload: Types.BannerPayload)
	local clean = normalize(payload)
	if clean == nil then
		return
	end
	seq += 1
	table.insert(queue, { payload = clean, seq = seq })
	sortQueue()
	while #queue > QUEUE_MAX do
		table.remove(queue) -- la moins prioritaire (la plus récente à priorité égale)
	end
	if current == nil and started then
		present(table.remove(queue, 1) :: Entry)
	end
end

-- Bannières en attente (tests)
function Banners.queued(): { Types.BannerPayload }
	local out = {}
	for _, entry in queue do
		table.insert(out, entry.payload)
	end
	return out
end

-- Bannière à l'écran (nil si aucune)
function Banners.current(): Types.BannerPayload?
	return if current then current.payload else nil
end

function Banners.Init()
	ensureGui()
end

function Banners.Start()
	if started then
		return
	end
	started = true
	Net.event("Banner").OnClientEvent:Connect(Banners.show)
	RunService.Heartbeat:Connect(onFrame)
	Prefs.LanguageChanged:Connect(function()
		lastText = ""
	end)
end

return Banners
