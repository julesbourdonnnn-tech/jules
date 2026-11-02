--!strict
-- Prompt (paquet client-hud, docs/04 §3.4, §13.5) : invites dans le monde dessinées par le jeu, sans
-- ProximityPrompt (GDD §10.2, §10.4).
--   * Au-dessus de la cible de PromptController : « □ Presser » (glyphe Layout.Prompt.MainGlyph 64 +
--     mot Layout.Prompt.MainText 40 px TV) et, après la leçon de fusion, une deuxième ligne plus petite
--     « ○ Prendre » (glyphe 48 + mot 32). Au clavier : « E Presser », « Q Prendre ». Jamais deux invites
--     sur la même touche, 2 au plus (□ puis ○) ; cible en recharge : invite atténuée.
--   * Plaques par UI/WorldText (BillboardGui en px TV × échelle de UI/Root, jamais en studs),
--     accrochées à une ancre locale invisible déplacée sur la cible ; une plaque qui sortirait de la zone
--     sûre de 5 % est ramenée à son bord (WorldText.clampToSafe, décalage SizeOffset).
--   * Anneau de maintien autour du glyphe □, calé sur l'heure de fin envoyée par le serveur : bol
--     (HoldState « feed », 2 s), attente sur une dalle (HoldState « tile », 0,6 s) et boop
--     (BoopState.endsAt, qui peut passer de 2,5 à 5 s en cours) ; retiré quand endsAt + 0,5 s est passé
--     (docs/04 §10.5), même sans message de fin.
--   * Cachées dès qu'une fenêtre est ouverte (FocusGuard) et en mode photo.
-- Une seule connexion par image ; temps par Clock.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Clock = require(Shared.Util.Clock)
local Layout = require(Shared.Config.Layout)
local Quests = require(Shared.Config.Quests)

local Client = script.Parent.Parent
local Root = require(Client.UI.Root)
local Juice = require(Client.UI.Juice)
local Glyph = require(Client.UI.Glyph)
local FocusGuard = require(Client.UI.FocusGuard)
local Prefs = require(Client.Util.Prefs)
local State = require(Client.Controllers.StateController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local PromptController = require(Client.Controllers.PromptController)
local WorldText = require(Client.UI.WorldText)
local Util = require(Client.UI.Hud.Util)

local Prompt = {}

-- (sorte du maintien, réussi) : un maintien suivi par l'anneau vient de finir (InputController :
-- vibration holdDone)
Prompt.HoldEnded = Signal.new() :: Signal.Signal<string, boolean>

local P = Layout.Prompt
local HOLD_GRACE = 0.5
local MAX_HOLD = 10 -- s : jamais un anneau plus long (heure de fin abîmée)
local STUDS_ABOVE = 4 -- studs au-dessus du centre de la cible
local MAX_DISTANCE = 80 -- studs : au-delà, aucune invite (la cible est de toute façon plus proche)
local LINE_GAP = 8 -- px TV entre les deux lignes
local FUSION_LESSON_STEP = 4 -- étape d'accueil après laquelle la ligne ○ apparaît (leçon de fusion)
local RING_PAD = 8

local PRIMARY_KEYS: { [string]: string } = {
	press = "prompt.press",
	throw = "prompt.throw",
	fusion = "prompt.fusion",
	putInPool = "prompt.putInPool",
	buy = "prompt.buy",
	boop = "prompt.boop",
	feed = "prompt.feed",
	catch = "prompt.catch",
	sell = "prompt.sell",
	shop = "prompt.shop",
	petsit = "prompt.petsit",
}
local SECONDARY_KEYS: { [string]: string } = {
	pickup = "prompt.pickup",
	putdown = "prompt.putdown",
}
local PRIMARY_BINDING: Glyph.Binding = { gamepad = Enum.KeyCode.ButtonX, keyboard = Enum.KeyCode.E }
local SECONDARY_BINDING: Glyph.Binding = { gamepad = Enum.KeyCode.ButtonB, keyboard = Enum.KeyCode.Q }

type Hold = { startAt: number, endsAt: number }
type Line = { binding: Glyph.Binding, key: string, main: boolean }

local started = false
local folder: Folder? = nil
local anchor: BasePart? = nil
local mainGui: BillboardGui? = nil
local secondGui: BillboardGui? = nil
local ring: Frame? = nil
local ringGradient: UIGradient? = nil
local holds: { [string]: Hold } = {}
local photo = false
local lastTargetKey = ""
local lineKeys: { [BillboardGui]: string } = {}

-- =============================================================================================
-- Construction
-- =============================================================================================

local function getAnchor(): BasePart
	local a = anchor
	if a and a.Parent then
		return a
	end
	local f = folder
	if f == nil or f.Parent == nil then
		local existing = workspace:FindFirstChild("Prompts")
		if existing and existing:IsA("Folder") then
			f = existing
		else
			local nf = Instance.new("Folder")
			nf.Name = "Prompts"
			nf.Parent = workspace
			f = nf
		end
		folder = f
	end
	-- ancre invisible : ancrée, sans collision ni requête ni contact (aucune règle n'y touche)
	local part = Instance.new("Part")
	part.Name = "PromptAnchor"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Parent = f
	anchor = part
	return part
end

local function ensureGuis()
	if mainGui == nil or mainGui.Parent == nil then
		local a = getAnchor()
		local g = WorldText.create(a, {
			kind = "plus",
			maxDistance = MAX_DISTANCE,
			studsOffset = Vector3.new(0, STUDS_ABOVE, 0),
			alwaysOnTop = true,
			name = "PromptMain",
		})
		WorldText.setTextSize(g, P.MainText)
		g.Enabled = false
		mainGui = g
		-- anneau de maintien autour du glyphe □ : contour blanc qui se remplit (dégradé)
		local plate = g:FindFirstChild("Plate")
		if plate then
			local r = Instance.new("Frame")
			r.Name = "HoldRing"
			r.BackgroundTransparency = 1
			r.AnchorPoint = Vector2.new(0, 0.5)
			r.ZIndex = 6
			r.Visible = false
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = r
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.new(1, 1, 1)
			stroke.Thickness = 6
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			local gradient = Instance.new("UIGradient")
			gradient.Rotation = -90
			gradient.Parent = stroke
			stroke.Parent = r
			r.Parent = plate
			ring = r
			ringGradient = gradient
		end
	end
	if secondGui == nil or secondGui.Parent == nil then
		local g = WorldText.create(getAnchor(), {
			kind = "text",
			maxDistance = MAX_DISTANCE,
			studsOffset = Vector3.new(0, STUDS_ABOVE, 0),
			alwaysOnTop = true,
			name = "PromptSecond",
		})
		WorldText.setTextSize(g, P.SecondText)
		g.Enabled = false
		secondGui = g
	end
end

-- =============================================================================================
-- Maintiens
-- =============================================================================================

local function holdProgress(now: number): number?
	local best: number? = nil
	for kind, h in holds do
		if now > h.endsAt + HOLD_GRACE or now < h.startAt - 1 then
			holds[kind] = nil
			Prompt.HoldEnded:Fire(kind, now >= h.endsAt)
		else
			local total = math.max(0.05, h.endsAt - h.startAt)
			local k = math.clamp((now - h.startAt) / total, 0, 1)
			best = if best == nil then k else math.max(best :: number, k)
		end
	end
	return best
end

local function drawRing(k: number?)
	local r = ring
	local g = ringGradient
	local gui = mainGui
	if r == nil or g == nil or gui == nil then
		return
	end
	if k == nil then
		r.Visible = false
		return
	end
	local plate = gui:FindFirstChild("Plate")
	local glyph = if plate then plate:FindFirstChild("Glyph") else nil
	if glyph == nil or not glyph:IsA("GuiObject") or not glyph.Visible then
		r.Visible = false
		return
	end
	local size = glyph.Size.Y.Offset + 2 * RING_PAD
	r.Size = UDim2.fromOffset(size, size)
	r.Position = UDim2.new(0, glyph.Position.X.Offset - RING_PAD, 0.5, 0)
	local p = math.clamp(k, 0, 1)
	local edge = math.clamp(p, 0.001, 0.998)
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(edge, 0),
		NumberSequenceKeypoint.new(math.min(0.999, edge + 0.001), 0.85),
		NumberSequenceKeypoint.new(1, 0.85),
	})
	r.Visible = true
end

-- =============================================================================================
-- Invites
-- =============================================================================================

local function onboardingStep(): number
	local o = State.get("onboarding")
	if type(o) ~= "table" then
		return 0
	end
	if o.done == true then
		return 99
	end
	return Util.num(o.step, 0, 0, 99)
end

local function linesFor(target: { [string]: any }): { Line }
	local lines: { Line } = {}
	local primary = PRIMARY_KEYS[target.primary or ""]
	if primary then
		table.insert(lines, { binding = PRIMARY_BINDING, key = primary, main = true })
	end
	local secondary = SECONDARY_KEYS[target.secondary or ""]
	if secondary and (onboardingStep() >= FUSION_LESSON_STEP or primary == nil) then
		table.insert(lines, { binding = SECONDARY_BINDING, key = secondary, main = #lines == 0 })
	end
	return lines
end

local function applyLine(gui: BillboardGui, line: Line, size: number, glyphSize: number)
	local key = line.key .. "|" .. tostring(line.binding.gamepad) .. "|" .. size
	if lineKeys[gui] ~= key then
		lineKeys[gui] = key
		WorldText.setTextSize(gui, size)
		WorldText.setGlyph(gui, line.binding, glyphSize)
	end
	WorldText.setText(gui, Util.t(line.key))
end

-- Pixels d'écran d'une plaque (px TV × échelle)
local function platePixels(gui: BillboardGui): Vector2
	local px = WorldText.plateSize(gui)
	local s = Root.scale()
	return Vector2.new(px.X * s, px.Y * s)
end

local function hideAll()
	if mainGui then
		mainGui.Enabled = false
	end
	if secondGui then
		secondGui.Enabled = false
	end
	drawRing(nil)
end

local function step(now: number)
	local k = holdProgress(now)
	local hidden = photo or Util.safe("FocusGuard.anyOpen", false, FocusGuard.anyOpen) == true
	local target = if hidden
		then nil
		else Util.safe("PromptController.current", nil, PromptController.current)
	if type(target) ~= "table" or typeof(target.position) ~= "Vector3" then
		lastTargetKey = ""
		hideAll()
		return
	end
	local lines = linesFor(target)
	if #lines == 0 then
		hideAll()
		return
	end
	ensureGuis()
	local a = getAnchor()
	local pos = target.position :: Vector3
	if (a.Position - pos).Magnitude > 0.01 then
		a.CFrame = CFrame.new(pos)
	end
	local mainG = mainGui :: BillboardGui
	local secondG = secondGui :: BillboardGui
	applyLine(mainG, lines[1], P.MainText, P.MainGlyph)
	WorldText.setDim(mainG, target.ready == false and lines[1].key ~= SECONDARY_KEYS.putdown)
	local second = lines[2]
	if second then
		applyLine(secondG, second, P.SecondText, P.SecondGlyph)
	end
	-- position à l'écran : centrée au-dessus de la cible, deuxième ligne dessous, le tout ramené dans
	-- la zone sûre de 5 %
	local cf, fov, viewport = Util.camera()
	local mainPx = platePixels(mainG)
	local secondPx = if second then platePixels(secondG) else Vector2.zero
	local gap = LINE_GAP * Root.scale()
	local delta = Vector2.zero
	if cf then
		local screenPos, front =
			Util.project(cf :: CFrame, fov, viewport, pos + Vector3.new(0, STUDS_ABOVE, 0))
		if front then
			local blockW = math.max(mainPx.X, secondPx.X)
			local blockH = mainPx.Y + (if second then gap + secondPx.Y else 0)
			local topLeft = Vector2.new(screenPos.X - blockW / 2, screenPos.Y - mainPx.Y / 2)
			local clamped = WorldText.clampToSafe(topLeft, Vector2.new(blockW, blockH), viewport)
			delta = clamped - topLeft
		end
	end
	mainG.SizeOffset = Vector2.new(delta.X / math.max(mainPx.X, 1), -delta.Y / math.max(mainPx.Y, 1))
	mainG.Enabled = true
	if second then
		local down = mainPx.Y / 2 + gap + secondPx.Y / 2 + delta.Y
		secondG.SizeOffset = Vector2.new(delta.X / math.max(secondPx.X, 1), -down / math.max(secondPx.Y, 1))
		secondG.Enabled = true
	else
		secondG.Enabled = false
	end
	-- nouvelle cible : petit fondu d'apparition du mot (pas en Mouvement réduit)
	local targetKey = tostring(target.kind) .. ":" .. tostring(target.slot) .. ":" .. tostring(target.uid)
	if targetKey ~= lastTargetKey then
		lastTargetKey = targetKey
		if not Prefs.reducedMotion() then
			local plate = mainG:FindFirstChild("Plate")
			local label = if plate then plate:FindFirstChild("Text") else nil
			if label and label:IsA("TextLabel") then
				label.TextTransparency = 1
				Juice.tween(label, 0.12, { TextTransparency = if target.ready == false then 0.35 else 0 })
			end
		end
	end
	drawRing(if lines[1].main and lines[1].binding == PRIMARY_BINDING then k else nil)
end

-- =============================================================================================
-- Remotes
-- =============================================================================================

local function onHoldState(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local kind = payload.kind
	if kind ~= "feed" and kind ~= "tile" then
		return
	end
	if payload.active == true then
		Prompt.setHold(kind, Util.num(payload.endsAt, 0))
	else
		Prompt.setHold(kind, nil)
	end
end

local function onBoop(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local me = Players.LocalPlayer
	if me == nil or payload.booperId ~= me.UserId then
		return
	end
	if payload.state == "hold" then
		Prompt.setHold("boop", Util.num(payload.endsAt, 0))
	else
		local h = holds.boop
		if h then
			holds.boop = nil
			Prompt.HoldEnded:Fire("boop", payload.state == "done")
		end
	end
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Création des remotes et des états ; aucun yield long
function Prompt.Init()
	table.clear(holds)
end

-- Connexions et boucles
function Prompt.Start()
	if started then
		return
	end
	started = true
	Net.event("HoldState").OnClientEvent:Connect(onHoldState)
	WorldStateController.BoopChanged:Connect(onBoop)
	Net.event("Celebrate").OnClientEvent:Connect(function(payload: any)
		if type(payload) == "table" and payload.kind == "photo" and type(payload.data) == "table" then
			photo = payload.data.on == true
		end
	end)
	RunService.Heartbeat:Connect(function()
		step(Clock.now())
	end)
end

-- Anneau de maintien (nil : retiré) ; endsAt = Clock.now() de fin envoyée par le serveur
function Prompt.setHold(kind: string, endsAt: number?)
	if type(kind) ~= "string" or #kind > 16 then
		return
	end
	local now = Clock.now()
	if endsAt == nil then
		local h = holds[kind]
		if h then
			holds[kind] = nil
			Prompt.HoldEnded:Fire(kind, now >= h.endsAt - 0.05)
		end
		return
	end
	local e = Util.num(endsAt, now)
	if e <= now - HOLD_GRACE then
		return -- déjà fini : rien à dessiner
	end
	e = math.min(e, now + MAX_HOLD)
	local h = holds[kind]
	if h then
		h.endsAt = e -- un boop peut passer de 2,5 à 5 s en cours : même départ, nouvelle fin
	else
		local expected = if kind == "feed" then Quests.Feed.Hold else nil
		local startAt = if expected then math.max(now, e - expected) else now
		holds[kind] = { startAt = math.min(startAt, e), endsAt = e }
	end
end

-- Plaques affichées (specs)
function Prompt.plates(): { GuiObject }
	local out: { GuiObject } = {}
	for _, gui in { mainGui, secondGui } do
		if gui and gui.Enabled and gui.Parent then
			local plate = gui:FindFirstChild("Plate")
			if plate and plate:IsA("GuiObject") then
				table.insert(out, plate)
			end
		end
	end
	return out
end

-- BillboardGui des invites affichées (specs : taille projetée, bornage)
function Prompt.guis(): { BillboardGui }
	local out: { BillboardGui } = {}
	for _, gui in { mainGui, secondGui } do
		if gui and gui.Enabled and gui.Parent then
			table.insert(out, gui)
		end
	end
	return out
end

-- Progression de l'anneau de maintien (0-1) ou nil (specs)
function Prompt.holdProgress(): number?
	local now = Clock.now()
	local best: number? = nil
	for _, h in holds do
		if now <= h.endsAt + HOLD_GRACE then
			local k = math.clamp((now - h.startAt) / math.max(0.05, h.endsAt - h.startAt), 0, 1)
			best = if best == nil then k else math.max(best :: number, k)
		end
	end
	return best
end

-- Un maintien suivi par l'anneau est-il en cours ?
function Prompt.holding(): boolean
	return Prompt.holdProgress() ~= nil
end

-- Un tour tout de suite (specs ; la boucle par image fait de même)
function Prompt._step()
	step(Clock.now())
end

return Prompt
