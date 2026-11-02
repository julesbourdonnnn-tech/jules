--!strict
-- ScreenFX (paquet client-hud, docs/04 §13.5) : effets d'écran (GDD §9.2, §9.4, §10.2).
--   * flash(alpha, duration, color) : voile plein écran, opacité ≤ 30 %, durée ≤ 1 s ;
--   * glow(color, duration, strength) : lueur des bords (série PERFECT, combo, vignette de couleur) ;
--   * arrow(id, worldPos, kind) : flèche de bord d'écran vers une cible hors champ (72 × 72 px TV,
--     au bord de la zone sûre), retirée avec worldPos = nil. 2 flèches au plus à l'écran
--     (Layout.HudContent.edgeArrow.max) : quand plus de flèches sont demandées, celles de la
--     sorte la plus prioritaire (Golden, mon squishy boopé, ma créature, Wild partagé, fuite du
--     Rush), puis la plus proche, sont montrées ; une cible au-delà de edgeArrow.range studs ou à
--     l'écran n'a pas de flèche.
-- Règles : aucun clignotement au-dessus de 3 Hz (un flash et une lueur au plus toutes les 1/3 s) ;
-- rien en Mouvement réduit sauf les flèches (fixes, sans pulsation) ; flèches cachées dès qu'une
-- fenêtre est ouverte (FocusGuard) et en mode photo. Les voiles qui débordent de la zone sûre sont
-- marqués Decorative = true. Une seule connexion par image (RenderStepped) ; temps par Clock.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Clock = require(Shared.Util.Clock)
local Layout = require(Shared.Config.Layout)

local Client = script.Parent.Parent
local Root = require(Client.UI.Root)
local Juice = require(Client.UI.Juice)
local Prefs = require(Client.Util.Prefs)
local FocusGuard = require(Client.UI.FocusGuard)
local Util = require(Client.UI.Hud.Util)
local Chase = require(Client.UI.Hud.Chase)

local ScreenFX = {}

local MAX_FLASH_ALPHA = 0.3
local MAX_FLASH_TIME = 1
local MAX_GLOW_TIME = 3
local MIN_PERIOD = 1 / 3 -- s : jamais plus de 3 Hz
local GLOW_WIDTH = 160 -- px TV de la lueur de chaque bord
local ARROW = Layout.HudContent.edgeArrow
local DISPLAY_ORDER = 8
local ARROW_PULSE = 0.8 -- s

-- Priorité des sortes de flèches (plus petit = plus prioritaire, GDD v1.3 §10.2)
local ARROW_PRIORITY: { [string]: number } = {
	golden = 1,
	booped = 2,
	mine = 2,
	personal = 3,
	wild = 4,
	rush = 5,
}
local ARROW_COLORS: { [string]: Color3 } = {
	golden = Color3.fromRGB(255, 208, 72),
	booped = Color3.fromRGB(255, 120, 180),
	mine = Color3.fromRGB(255, 120, 180),
	personal = Color3.fromRGB(120, 220, 160),
	wild = Color3.fromRGB(130, 180, 255),
	rush = Color3.fromRGB(255, 150, 210),
}

type ArrowReq = { pos: Vector3, kind: string, at: number }
type ArrowView = { frame: Frame, tip: Frame, scale: UIScale, id: string? }
type Candidate = { id: string, req: ArrowReq, dist: number, screen: Vector2, front: boolean }

local screen: ScreenGui? = nil
local flashFrame: Frame? = nil
local glowFrames: { Frame } = {}
local arrowViews: { ArrowView } = {}
local requests: { [string]: ArrowReq } = {}
local lastFlashAt = -math.huge
local lastGlowAt = -math.huge
local glowToken = 0
local photo = false
local started = false
local pulseClock = 0
local autoAcc = math.huge
local AUTO_EVERY = 0.1 -- s entre deux choix des flèches automatiques (créatures attrapables)

-- =============================================================================================
-- Construction
-- =============================================================================================

local function makeScreen(): ScreenGui?
	local existing = screen
	if existing and existing.Parent then
		return existing
	end
	local ok, gui = pcall(Root.screen, "ScreenFX", DISPLAY_ORDER)
	if not ok then
		return nil
	end
	screen = gui
	return gui
end

local function build()
	local gui = makeScreen()
	if gui == nil then
		return
	end
	local safe = gui:FindFirstChild("Safe") :: Frame
	-- flash : voile plein écran (hors de la zone sûre : décoratif)
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Active = false
	flash.ZIndex = 1
	flash.Visible = false
	flash:SetAttribute("Decorative", true)
	flash.Parent = gui
	flashFrame = flash
	-- lueur : 4 bandes en dégradé, du bord de l'écran vers le centre
	local edges = {
		{ name = "GlowTop", size = UDim2.new(1, 0, 0, GLOW_WIDTH), pos = UDim2.fromScale(0, 0), rot = 90 },
		{
			name = "GlowBottom",
			size = UDim2.new(1, 0, 0, GLOW_WIDTH),
			pos = UDim2.new(0, 0, 1, -GLOW_WIDTH),
			rot = -90,
		},
		{ name = "GlowLeft", size = UDim2.new(0, GLOW_WIDTH, 1, 0), pos = UDim2.fromScale(0, 0), rot = 0 },
		{
			name = "GlowRight",
			size = UDim2.new(0, GLOW_WIDTH, 1, 0),
			pos = UDim2.new(1, -GLOW_WIDTH, 0, 0),
			rot = 180,
		},
	}
	for _, def in edges do
		local f = Instance.new("Frame")
		f.Name = def.name
		f.Size = def.size
		f.Position = def.pos
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Active = false
		f.Visible = false
		f.ZIndex = 1
		f:SetAttribute("Decorative", true)
		local g = Instance.new("UIGradient")
		g.Rotation = def.rot
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = f
		f.Parent = gui
		table.insert(glowFrames, f)
	end
	-- flèches de bord : réserve de edgeArrow.max cadres dans la zone sûre
	for i = 1, ARROW.max do
		local f = Instance.new("Frame")
		f.Name = "EdgeArrow" .. i
		f.Size = UDim2.fromOffset(ARROW.size, ARROW.size)
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundColor3 = Color3.fromRGB(28, 24, 48)
		f.BackgroundTransparency = 0.15
		f.Visible = false
		f.Active = false
		f.ZIndex = 5
		Util.chrome(f, ARROW.size // 2)
		local scale = Instance.new("UIScale")
		scale.Name = "JuiceScale"
		scale.Parent = f
		-- pointe : losange tourné vers la cible (formes seulement, aucune image)
		local tip = Instance.new("Frame")
		tip.Name = "Tip"
		tip.AnchorPoint = Vector2.new(0.5, 0.5)
		tip.Position = UDim2.fromScale(0.5, 0.5)
		tip.Size = UDim2.fromScale(1, 1)
		tip.BackgroundTransparency = 1
		tip.ZIndex = 6
		local head = Instance.new("Frame")
		head.Name = "Head"
		head.AnchorPoint = Vector2.new(0.5, 0.5)
		head.Position = UDim2.fromScale(0.72, 0.5)
		head.Size = UDim2.fromScale(0.34, 0.34)
		head.Rotation = 45
		head.BackgroundColor3 = Color3.new(1, 1, 1)
		head.BorderSizePixel = 0
		head.ZIndex = 7
		head.Parent = tip
		local dot = Instance.new("Frame")
		dot.Name = "Dot"
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.42, 0.5)
		dot.Size = UDim2.fromScale(0.3, 0.3)
		dot.BackgroundColor3 = Color3.new(1, 1, 1)
		dot.BorderSizePixel = 0
		dot.ZIndex = 7
		local dc = Instance.new("UICorner")
		dc.CornerRadius = UDim.new(0.5, 0)
		dc.Parent = dot
		dot.Parent = tip
		tip.Parent = f
		f.Parent = safe
		table.insert(arrowViews, { frame = f, tip = tip, scale = scale, id = nil })
	end
end

-- =============================================================================================
-- Flèches
-- =============================================================================================

local function priorityOf(kind: string): number
	return ARROW_PRIORITY[kind] or 9
end

-- Point du bord de la zone sûre (px TV dans Safe) dans la direction de la cible, et angle (degrés)
local function edgePoint(screenPos: Vector2, viewport: Vector2, onFront: boolean): (Vector2, number)
	local s = math.max(Root.scale(), 1e-3)
	-- l'écran du jeu commence sous la barre de Roblox (ScreenInsets) : même repère que Safe
	local inset = 0
	pcall(function()
		local topLeft = GuiService:GetGuiInset()
		inset = Util.num(topLeft.Y, 0, 0, viewport.Y / 2)
	end)
	local w, h = viewport.X / s, (viewport.Y - inset) / s
	local pad = Root.padding()
	local cx, cy = w / 2, h / 2
	local dx, dy = screenPos.X / s - cx, (screenPos.Y - inset) / s - cy
	if not onFront then
		-- derrière la caméra : la flèche montre le bas de l'écran du côté de la cible
		dy = math.abs(dy) + h
	end
	if math.abs(dx) < 1e-6 and math.abs(dy) < 1e-6 then
		dy = 1
	end
	local half = ARROW.size / 2
	local hw = math.max(1, cx - pad.X - half)
	local hh = math.max(1, cy - pad.Y - half)
	local k = math.min(hw / math.max(math.abs(dx), 1e-6), hh / math.max(math.abs(dy), 1e-6))
	local x = cx + dx * k
	local y = cy + dy * k
	-- coordonnées dans Safe (dont la marge intérieure est la zone sûre)
	return Vector2.new(x - pad.X, y - pad.Y), math.deg(math.atan2(dy, dx))
end

local function hideArrows()
	for _, view in arrowViews do
		if view.frame.Visible then
			view.frame.Visible = false
		end
		view.id = nil
	end
end

-- Flèches automatiques (GDD v1.3 §10.2, tous les modes) : le Golden Wobbler s'il est attrapable par
-- moi, puis la créature attrapable la plus proche par priorité (mon squishy boopé, ma créature
-- personnelle, un Wild Wobbler partagé, une fuite du Rush pour un joueur Rush), à edgeArrow.range
-- studs au plus (Hud/Chase : mêmes règles que le serveur)
local function autoArrows(now: number)
	local golden: Chase.Target? = nil
	local nearest: Chase.Target? = nil
	for _, t in Chase.targets(now) do
		if t.dist <= ARROW.range then
			if t.arrow == "golden" then
				if golden == nil then
					golden = t
				end
			elseif nearest == nil then
				nearest = t
			end
		end
	end
	if golden then
		requests["auto:golden"] = { pos = golden.pos, kind = "golden", at = now }
	else
		requests["auto:golden"] = nil
	end
	if nearest then
		requests["auto:nearest"] = { pos = nearest.pos, kind = nearest.arrow, at = now }
	else
		requests["auto:nearest"] = nil
	end
end

local function stepArrows(dt: number)
	if #arrowViews == 0 then
		return
	end
	autoAcc += dt
	if autoAcc >= AUTO_EVERY then
		autoAcc = 0
		autoArrows(Clock.now())
	end
	local hidden = photo or Util.safe("FocusGuard.anyOpen", false, FocusGuard.anyOpen)
	if hidden or next(requests) == nil then
		hideArrows()
		return
	end
	local cf, fov, viewport = Util.camera()
	local me = Util.rootPos()
	if cf == nil then
		hideArrows()
		return
	end
	local origin = me or (cf :: CFrame).Position
	local candidates: { Candidate } = {}
	for id, req in requests do
		local dist = (req.pos - origin).Magnitude
		if dist <= ARROW.range then
			local scr, front, on = Util.project(cf :: CFrame, fov, viewport, req.pos)
			if not on then
				table.insert(candidates, { id = id, req = req, dist = dist, screen = scr, front = front })
			end
		end
	end
	table.sort(candidates, function(a, b)
		local pa, pb = priorityOf(a.req.kind), priorityOf(b.req.kind)
		if pa ~= pb then
			return pa < pb
		end
		if a.dist ~= b.dist then
			return a.dist < b.dist
		end
		return a.id < b.id
	end)
	local reduced = Prefs.reducedMotion()
	pulseClock = (pulseClock + dt) % ARROW_PULSE
	local pulse = if reduced then 1 else 1 + 0.08 * math.sin(2 * math.pi * pulseClock / ARROW_PULSE)
	for i, view in arrowViews do
		local c = candidates[i]
		if c == nil then
			if view.frame.Visible then
				view.frame.Visible = false
			end
			view.id = nil
		else
			local pos, angle = edgePoint(c.screen, viewport, c.front)
			view.frame.Position = UDim2.fromOffset(pos.X, pos.Y)
			view.tip.Rotation = angle
			view.frame.BackgroundColor3 = ARROW_COLORS[c.req.kind] or Color3.fromRGB(255, 255, 255)
			view.scale.Scale = pulse
			view.frame:SetAttribute("ArrowId", c.id)
			view.frame:SetAttribute("ArrowKind", c.req.kind)
			view.id = c.id
			if not view.frame.Visible then
				view.frame.Visible = true
			end
		end
	end
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Création des remotes et des états ; aucun yield long
function ScreenFX.Init()
	if screen ~= nil then
		return
	end
	build()
end

-- Connexions et boucles
function ScreenFX.Start()
	if started then
		return
	end
	started = true
	ScreenFX.Init()
	RunService.RenderStepped:Connect(function(dt: number)
		stepArrows(Util.num(dt, 1 / 60, 0, 1))
	end)
	pcall(function()
		local Net = require(Shared.Net)
		Net.event("Celebrate").OnClientEvent:Connect(function(payload: any)
			if type(payload) == "table" and payload.kind == "photo" and type(payload.data) == "table" then
				photo = payload.data.on == true
			end
		end)
	end)
end

-- Flash (pas en Mouvement réduit) : opacité bornée à 30 %, jamais plus de 3 par seconde
function ScreenFX.flash(alpha: number, duration: number, color: Color3?)
	local frame = flashFrame
	if frame == nil or Prefs.reducedMotion() then
		return
	end
	local now = Clock.now()
	if now - lastFlashAt < MIN_PERIOD and now >= lastFlashAt then
		return
	end
	lastFlashAt = now
	local a = Util.num(alpha, 0.15, 0, MAX_FLASH_ALPHA)
	local d = Util.num(duration, 0.12, 0.05, MAX_FLASH_TIME)
	frame.BackgroundColor3 = if typeof(color) == "Color3" then color else Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 1 - a
	frame.Visible = true
	local tween =
		Juice.tween(frame, d, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	tween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed and frame.BackgroundTransparency >= 1 then
			frame.Visible = false
		end
	end)
end

-- Lueur des bords (pas en Mouvement réduit) : force 0-1 (opacité au bord), durée ≤ 3 s
function ScreenFX.glow(color: Color3, duration: number, strength: number?)
	if #glowFrames == 0 or Prefs.reducedMotion() then
		return
	end
	local now = Clock.now()
	if now - lastGlowAt < MIN_PERIOD and now >= lastGlowAt then
		return
	end
	lastGlowAt = now
	glowToken += 1
	local token = glowToken
	local k = Util.num(strength, 0.5, 0, 1)
	local d = Util.num(duration, 0.4, 0.05, MAX_GLOW_TIME)
	local c = if typeof(color) == "Color3" then color else Color3.fromRGB(255, 208, 72)
	for _, f in glowFrames do
		f.BackgroundColor3 = c
		f.BackgroundTransparency = 1 - 0.6 * k
		f.Visible = true
		local tween =
			Juice.tween(f, d, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		tween.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed and token == glowToken then
				f.Visible = false
			end
		end)
	end
end

-- Flèche de bord d'écran vers une position (nil : retirée). `kind` : golden, booped, mine,
-- personal, wild, rush (priorité de cet ordre quand plus de 2 flèches sont demandées)
function ScreenFX.arrow(id: string, worldPos: Vector3?, kind: string)
	if type(id) ~= "string" or id == "" or #id > 64 then
		return
	end
	if typeof(worldPos) ~= "Vector3" then
		requests[id] = nil
		return
	end
	local p = worldPos :: Vector3
	if p.X ~= p.X or p.Y ~= p.Y or p.Z ~= p.Z or math.abs(p.X) == math.huge or math.abs(p.Z) == math.huge then
		requests[id] = nil
		return
	end
	local existing = requests[id]
	if existing == nil then
		local n = 0
		for _ in requests do
			n += 1
		end
		if n >= 32 then
			return -- borne mémoire : une flèche de plus ne peut jamais faire grossir la table sans fin
		end
	end
	requests[id] = { pos = p, kind = if type(kind) == "string" then kind else "", at = Clock.now() }
end

-- Flèches affichées (specs) : { id, kind }
function ScreenFX.arrows(): { { id: string, kind: string } }
	local out = {}
	for _, view in arrowViews do
		if view.frame.Visible and view.id ~= nil then
			local req = requests[view.id :: string]
			table.insert(out, { id = view.id :: string, kind = if req then req.kind else "" })
		end
	end
	return out
end

-- Un tour de calcul des flèches tout de suite (specs ; la boucle par image fait de même)
function ScreenFX._step()
	autoAcc = math.huge
	stepArrows(0)
end

return ScreenFX
