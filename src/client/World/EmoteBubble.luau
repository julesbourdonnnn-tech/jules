--!strict
-- EmoteBubble (lot I, étape 5 ; décision D27 du plan I ; GDD §6.5 « Emotes et signaux », v1.3) : les
-- signaux de la croix dessinés au-dessus de la tête, sur WorldStateController.EmoteShown. Trou de la
-- v1.3 trouvé par le plan B5 : le serveur envoyait EmoteShow à tous, mais aucun client ne dessinait
-- rien ; sur une console, appuyer sur la croix doit montrer quelque chose.
--   * bulle-icône dessinée (aucun texte) au-dessus du joueur pendant 2,5 s (GDD §6.5), visible
--     jusqu'à 150 studs : main (↑ Salut), cœur (→ Merci), étoile (← Bravo) ;
--   * sorte 3 avec une emote de la v2.0 (World/Emotes.IDS) : rien ici, World/Emotes dessine l'effet ;
--   * sur MON personnage seulement : Humanoid:PlayEmote(nom) sous pcall (emote absente : rien) ;
--   * au plus une bulle par joueur toutes les 2 s (le serveur en accepte une par 1,2 s) ; 16 bulles
--     vivantes au plus ; bulles en réserve (aucune création en rafale) ; une minuterie par bulle,
--     aucune boucle par image.
-- Sans interrupteur : c'est la v1.3. Une seule écoute de signal.
--   EmoteBubble.start() / EmoteBubble.stop() / EmoteBubble.stats() / EmoteBubble._configure(sources)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Clock = require(Shared.Util.Clock)
local Cosmetics = require(Shared.Config.Cosmetics)

local Client = script.Parent.Parent
local Util = require(Client.World.Util)
local Emotes = require(Client.World.Emotes)
local Icons = require(Client.UI.Hud.Icons)
local Root = require(Client.UI.Root)
local WorldStateController = require(Client.Controllers.WorldStateController)

local EmoteBubble = {}

EmoteBubble.SHOW = 2.5 -- s (GDD §6.5)
EmoteBubble.EVERY = 2 -- s entre deux bulles d'un même joueur
EmoteBubble.RANGE = 150 -- studs
EmoteBubble.MAX_LIVE = 16
local POOL_MAX = 16
local PX = 72 -- px TV de la bulle (mise à l'échelle par Root.scale())
local ICON = 48
local HEAD = 4.4 -- studs au-dessus de HumanoidRootPart
local KINDS = { "hand", "heart", "star" }
local ICON_OF: { [number]: string } = {}
for _, def in Cosmetics.EmoteSignals do
	ICON_OF[def.kind] = if def.icon == "hand"
			or def.icon == "heart"
			or def.icon == "star"
		then def.icon
		else "star"
end
local V2_IDS: { [string]: boolean } = {}
for _, id in Emotes.IDS do
	V2_IDS[id] = true
end

type Bubble = { gui: BillboardGui, canvas: Frame, gen: number }

local started = false
local conn: RBXScriptConnection? = nil
local live: { [number]: Bubble } = {} -- userId → bulle
local liveCount = 0
local pool: { Bubble } = {}
local lastAt: { [number]: number } = {}
local folder: Folder? = nil
local counters = { shown = 0, skipped = 0, played = 0 }
local sources: { play: ((Humanoid, string) -> ())?, after: ((number, () -> ()) -> ())? } = {}

local function clientFolder(): Folder
	local f = folder
	if f and f.Parent ~= nil then
		return f
	end
	local root = workspace:FindFirstChild("ClientWorld")
	if root == nil then
		local created = Instance.new("Folder")
		created.Name = "ClientWorld"
		created.Parent = workspace
		root = created
	end
	local made = Instance.new("Folder")
	made.Name = "EmoteBubbles"
	made.Parent = root
	folder = made
	return made
end

local function build(): Bubble
	local gui = Instance.new("BillboardGui")
	gui.Name = "EmoteBubble"
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.MaxDistance = EmoteBubble.RANGE
	gui.Enabled = false
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromOffset(PX, PX)
	back.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	back.BackgroundTransparency = 0.05
	back.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = back
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(60, 40, 70)
	stroke.Parent = back
	back.Parent = gui
	local canvas = Icons.canvas(back, ICON, KINDS, "Icon")
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	return { gui = gui, canvas = canvas, gen = 0 }
end

local function release(userId: number, b: Bubble)
	if live[userId] ~= b then
		return
	end
	live[userId] = nil
	liveCount -= 1
	b.gen += 1
	b.gui.Enabled = false
	b.gui.Adornee = nil
	if #pool >= POOL_MAX then
		b.gui:Destroy()
		return
	end
	table.insert(pool, b)
end

local function after(seconds: number, fn: () -> ())
	local custom = sources.after
	if custom then
		pcall(custom, seconds, fn)
	else
		task.delay(seconds, fn)
	end
end

local function rootOf(userId: number): BasePart?
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function playMine(userId: number, emote: string)
	local me = Players.LocalPlayer
	if me == nil or me.UserId ~= userId or emote == "" then
		return
	end
	local character = me.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if hum == nil then
		return
	end
	counters.played += 1
	local custom = sources.play
	if custom then
		pcall(custom, hum, emote)
		return
	end
	pcall(function()
		(hum :: any):PlayEmote(emote)
	end)
end

local function onEmote(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local userId = Util.int(payload.userId, 1, 2 ^ 53)
	local kind = Util.int(payload.kind, 1, 3)
	local emote = if type(payload.emote) == "string" and #payload.emote <= 32 then payload.emote else ""
	if userId == nil or kind == nil then
		return
	end
	-- emote de la v2.0 (sorte 3) : l'effet de World/Emotes, aucune bulle
	if kind == 3 and V2_IDS[emote] then
		return
	end
	playMine(userId, emote)
	local now = Clock.now()
	local last = lastAt[userId]
	if last ~= nil and now >= last and now - last < EmoteBubble.EVERY then
		counters.skipped += 1
		return
	end
	local root = rootOf(userId)
	local mine = Util.localRoot()
	if root == nil then
		return
	end
	if mine ~= nil and (root.Position - mine.Position).Magnitude > EmoteBubble.RANGE then
		counters.skipped += 1
		return
	end
	local old = live[userId]
	if old then
		release(userId, old)
	end
	if liveCount >= EmoteBubble.MAX_LIVE then
		counters.skipped += 1
		return
	end
	lastAt[userId] = now
	local b = table.remove(pool) or build()
	b.gen += 1
	local gen = b.gen
	local s = Util.safe("Root.scale", 1, Root.scale)
	local scale = b.gui:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = s
	end
	b.gui.Size = UDim2.fromOffset(PX * s, PX * s)
	b.gui.StudsOffsetWorldSpace = Vector3.new(0, HEAD, 0)
	b.gui.Adornee = root
	Icons.draw(b.canvas, ICON_OF[kind] or "star")
	b.gui.Parent = clientFolder()
	b.gui.Enabled = true
	live[userId] = b
	liveCount += 1
	counters.shown += 1
	after(EmoteBubble.SHOW, function()
		if b.gen == gen then
			release(userId, b)
		end
	end)
end

function EmoteBubble.start()
	if started then
		return
	end
	started = true
	conn = WorldStateController.EmoteShown:Connect(function(payload: any)
		Util.guard("EmoteBubble.emote", onEmote, payload)
	end)
end

function EmoteBubble.stop()
	local c = conn
	conn = nil
	if c then
		c:Disconnect()
	end
	for userId, b in live do
		release(userId, b)
	end
	table.clear(lastAt)
	started = false
end

function EmoteBubble.stats(): { [string]: number }
	return {
		live = liveCount,
		pooled = #pool,
		shown = counters.shown,
		skipped = counters.skipped,
		played = counters.played,
		connections = if conn then 1 else 0,
	}
end

-- Specs : PlayEmote et minuterie remplaçables
function EmoteBubble._configure(options: any?)
	local o = if type(options) == "table" then options else {}
	sources.play = if type(o.play) == "function" then o.play else nil
	sources.after = if type(o.after) == "function" then o.after else nil
end

return EmoteBubble
