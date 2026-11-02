--!strict
-- ChaseRenderer (paquet client-world, docs/04 §13.3, GDD §9.4, §12.9).
-- Rendu des créatures du miroir WorldStateController : fuites personnelles, fuites du Rush (anneau à la
-- couleur du propriétaire, contour Highlight des 6 plus proches), Wild Wobblers, Golden Wobbler
-- (contour, traînée dorée), démonstration de Big Plop. Position = SeededPath (même code que le
-- serveur) ; bonds visuels (profil « hop » : étirement au départ, écrasement à l'atterrissage) ;
-- « Giggle » de la créature la plus proche toutes les 2 à 3 s (60 studs). Une créature finie, ou dont
-- l'heure de fin est passée, disparaît en rétrécissant (0,2 s). Réserve de modèles (SquishyBuilder) et
-- d'anneaux ; contours dans highlightQuota.chase, particules dans particleQuota.chase (stats()).
-- Une seule connexion par image (RenderStepped).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Clock = require(Shared.Util.Clock)
local Types = require(Shared.Types)
local Balance = require(Shared.Config.Balance)
local Cosmetics = require(Shared.Config.Cosmetics)
local Species = require(Shared.Config.Species)
local SizeScale = require(Shared.Logic.SizeScale)
local WorldLayout = require(Shared.Logic.WorldLayout)
local SquishyBuilder = require(Shared.Render.SquishyBuilder)
local Squash = require(Shared.Render.Squash)

local Client = script.Parent.Parent
local Prefs = require(Client.Util.Prefs)
local WorldStateController = require(Client.Controllers.WorldStateController)
local QualityController = require(Client.Controllers.QualityController)
local AudioController = require(Client.Controllers.AudioController)
local Util = require(Client.World.Util)

local ChaseRenderer = {}

local CFG = {
	Full = 60, -- studs : détail complet
	Mid = 140,
	HopTime = 0.45, -- s par bond (visuel, SeededPath)
	HopHeight = 1.2, -- studs
	ShrinkTime = 0.2, -- s
	GiggleRange = 60,
	GiggleMin = 2,
	GiggleMax = 3,
	RingSize = 0.25,
	RushHighlights = 6,
	GoldenRate = 8, -- particules par seconde (traînée dorée)
	GoldenLife = 1,
	MaxScale = 2.5, -- échelle affichée d'une créature au plus
	RefreshHighlights = 0.25,
}

type Creature = {
	id: number,
	spawn: Types.ChaseSpawn,
	handle: SquishyBuilder.Handle?,
	ring: Part?,
	emitter: ParticleEmitter?,
	lod: number,
	scale: number,
	pos: Vector3,
	shrinkT: number?, -- temps local du début de la disparition
	highlight: Highlight?,
}

local creatures: { [number]: Creature } = {}
local ringPool: { Part } = {}
local highlightPool: { Highlight } = {}
local animT = 0
local giggleAt = 0
local hlAcc = 0
local folder: Folder? = nil
local started = false
local connections: { any } = {}
local bulkParts: { BasePart } = {}
local bulkCFrames: { CFrame } = {}
local lastStats = { creatures = 0, highlights = 0, particles = 0, models = 0 }

local function budgets(): any
	return Util.safe("QualityController.budgets", nil, QualityController.budgets)
		or { lodScale = 1, particles = 1, particleQuota = { chase = 50 }, highlightQuota = { chase = 7 } }
end

local function reducedMotion(): boolean
	return Util.safe("Prefs.reducedMotion", false, Prefs.reducedMotion)
end

local function lowGraphics(): boolean
	return Util.safe("Prefs.lowGraphics", false, Prefs.lowGraphics)
end

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
	local sub = (root :: Instance):FindFirstChild("Creatures")
	if sub == nil or not sub:IsA("Folder") then
		local created = Instance.new("Folder")
		created.Name = "Creatures"
		created.Parent = root
		sub = created
	end
	folder = sub :: Folder
	return sub :: Folder
end

local function cameraPos(): Vector3
	local cam = workspace.CurrentCamera
	if cam then
		return cam.CFrame.Position
	end
	local root = Util.localRoot()
	return if root then root.Position else Vector3.zero
end

local function ringColor(s: Types.ChaseSpawn): Color3
	if s.kind == "golden" then
		return Color3.fromRGB(255, 210, 60)
	end
	if s.ownerSlot > 0 then
		return Cosmetics.RanchColors[s.ownerSlot] or Cosmetics.FreeRanchColor
	end
	return Color3.fromRGB(255, 255, 255)
end

local function takeRing(color: Color3, diameter: number): Part
	local ring = table.remove(ringPool)
	if ring == nil then
		local p = Instance.new("Part")
		p.Name = "CreatureRing"
		p.Shape = Enum.PartType.Cylinder
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		ring = p
	end
	local r = ring :: Part
	r.Color = color
	r.Size = Vector3.new(CFG.RingSize, diameter, diameter)
	r.Parent = clientFolder()
	return r
end

local function takeHighlight(): Highlight
	local h = table.remove(highlightPool)
	if h == nil then
		local created = Instance.new("Highlight")
		created.Name = "CreatureHighlight"
		created.FillTransparency = 1
		created.OutlineTransparency = 0
		h = created
	end
	local hl = h :: Highlight
	hl.Enabled = true
	hl.Parent = clientFolder()
	return hl
end

local function dropHighlight(c: Creature)
	local h = c.highlight
	if h then
		c.highlight = nil
		h.Adornee = nil
		h.Enabled = false
		h.Parent = nil
		table.insert(highlightPool, h)
	end
end

local function destroyCreature(c: Creature)
	dropHighlight(c)
	if c.emitter then
		c.emitter:Destroy()
		c.emitter = nil
	end
	if c.ring then
		c.ring.Parent = nil
		table.insert(ringPool, c.ring)
		c.ring = nil
	end
	local h = c.handle
	if h then
		c.handle = nil
		pcall(SquishyBuilder.release, h)
	end
	creatures[c.id] = nil
end

local function displayScale(s: Types.ChaseSpawn): number
	if s.kind == "demo" then
		return 3 -- Big Plop (diamètre 6 studs, note INT-WORLD-1)
	end
	return math.min(SizeScale.display(s.size, "pen"), CFG.MaxScale)
end

local function addCreature(s: Types.ChaseSpawn)
	if creatures[s.id] then
		return
	end
	local c: Creature = {
		id = s.id,
		spawn = s,
		handle = nil,
		ring = nil,
		emitter = nil,
		lod = 2,
		scale = displayScale(s),
		pos = Vector3.zero,
		shrinkT = nil,
		highlight = nil,
	}
	local spec: any = {
		species = if Species.ById[s.species] then s.species else Species.PLOP,
		mutation = s.mutation,
		stars = s.stars,
		displayScale = c.scale,
		lod = 2,
	}
	if s.kind == "demo" then
		spec.outfit = "bowTie"
	end
	local ok, h = pcall(SquishyBuilder.build, spec, clientFolder())
	if ok and type(h) == "table" then
		c.handle = h
		pcall(SquishyBuilder.setParticles, h, 0)
	end
	if s.kind ~= "wild" or s.ownerSlot > 0 then
		c.ring = takeRing(ringColor(s), Balance.SizeScale.BaseDiameter * c.scale + 1)
	end
	if s.kind == "golden" and c.handle and not lowGraphics() then
		local e = Instance.new("ParticleEmitter")
		e.Name = "GoldenTrail"
		e.Color = ColorSequence.new(Color3.fromRGB(255, 220, 80))
		e.Lifetime = NumberRange.new(CFG.GoldenLife)
		e.Rate = CFG.GoldenRate * Util.num(budgets().particles, 1, 0, 1)
		e.Parent = (c.handle :: any).body
		c.emitter = e
	end
	creatures[s.id] = c
	local mySlot = WorldStateController.mySlot()
	if s.kind == "runaway" and (s.ownerSlot == mySlot or s.personal) then
		Util.safe("AudioController.play", nil, AudioController.play, "RunawayAppear")
	elseif s.kind == "golden" then
		Util.safe("AudioController.play", nil, AudioController.play, "GoldenAppear")
	end
end

local function startShrink(id: number)
	local c = creatures[id]
	if c and c.shrinkT == nil then
		c.shrinkT = animT
		dropHighlight(c)
	end
end

-- Contours : 6 fuites du Rush les plus proches + Golden (highlightQuota.chase)
local function refreshHighlights(cam: Vector3, b: any)
	local quota = Util.num(b.highlightQuota and b.highlightQuota.chase, 7, 0, 7)
	local golden: Creature? = nil
	local rush: { { c: Creature, d: number } } = {}
	for _, c in creatures do
		if c.shrinkT == nil and c.handle then
			if c.spawn.kind == "golden" then
				golden = c
			elseif c.spawn.kind == "escape" then
				table.insert(rush, { c = c, d = (c.pos - cam).Magnitude })
			end
		end
	end
	table.sort(rush, function(x, y)
		return x.d < y.d
	end)
	local want: { [number]: boolean } = {}
	local n = 0
	if golden and n < quota then
		want[golden.id] = true
		n += 1
	end
	for i, item in rush do
		if i > CFG.RushHighlights or n >= quota then
			break
		end
		want[item.c.id] = true
		n += 1
	end
	for id, c in creatures do
		if want[id] and c.highlight == nil and c.handle then
			local h = takeHighlight()
			h.OutlineColor = ringColor(c.spawn)
			h.Adornee = (c.handle :: any).model
			c.highlight = h
		elseif not want[id] then
			dropHighlight(c)
		end
	end
end

-- Une image (exposé aux specs ; appelé par RenderStepped)
function ChaseRenderer._step(dt: number)
	local d = Util.num(dt, 0, 0, 1)
	animT += d
	local now = Clock.now()
	local cam = cameraPos()
	local b = budgets()
	table.clear(bulkParts)
	table.clear(bulkCFrames)
	-- créatures du miroir (une créature finie ou périmée rétrécit puis disparaît)
	local alive = WorldStateController.creatures()
	for id, s in alive do
		if creatures[id] == nil then
			addCreature(s)
		end
	end
	for id, c in creatures do
		if alive[id] == nil and c.shrinkT == nil then
			startShrink(id)
		end
	end
	local nearest: Creature? = nil
	local nearestD = math.huge
	local particles = 0
	local k = Util.num(b.lodScale, 1, 0.1, 1)
	for id, c in creatures do
		local h = c.handle
		local pos = WorldStateController.creaturePos(id, now) or c.pos
		local s = c.spawn
		local dist = (pos - cam).Magnitude
		local shrink = 1
		if c.shrinkT then
			local a = (animT - (c.shrinkT :: number)) / CFG.ShrinkTime
			if a >= 1 or h == nil then
				destroyCreature(c)
				continue
			end
			shrink = 1 - a
		end
		local lod = if dist < CFG.Full * k then 1 elseif dist < CFG.Mid * k then 2 else 3
		if h and c.lod ~= lod then
			c.lod = lod
			pcall(SquishyBuilder.setLod, h, lod)
		end
		local tau = now - s.t0
		local phase = (tau % CFG.HopTime) / CFG.HopTime
		local height = if s.kind == "demo" then 0 else math.sin(math.pi * phase) * CFG.HopHeight
		local sx, sy, sz = 1, 1, 1
		local amp = if reducedMotion() then 0.5 else 1
		if phase < 0.18 then
			local ok, a, bb, cc = pcall(Squash.sample, "hop", phase * CFG.HopTime, amp)
			if ok then
				sx, sy, sz = a, bb, cc
			end
		end
		local dia = Balance.SizeScale.BaseDiameter * c.scale
		local ground = WorldLayout.groundY(pos.X, pos.Z)
		local center = Vector3.new(pos.X, ground + dia * 0.5 * sy + height, pos.Z)
		c.pos = center
		if h then
			pcall(SquishyBuilder.setSquash, h, sx * shrink, sy * shrink, sz * shrink)
			if lod <= 2 then
				pcall(SquishyBuilder.animate, h, now, reducedMotion())
			end
			local ahead = WorldStateController.creaturePos(id, now + 0.1)
			local cf = CFrame.new(center)
			if ahead and (Vector3.new(ahead.X - pos.X, 0, ahead.Z - pos.Z)).Magnitude > 0.05 then
				cf = CFrame.lookAt(center, Vector3.new(ahead.X, center.Y, ahead.Z))
			end
			local ok, parts, cframes = pcall(SquishyBuilder.pose, h, cf)
			if ok and type(parts) == "table" then
				for i, part in parts do
					table.insert(bulkParts, part)
					table.insert(bulkCFrames, cframes[i])
				end
			end
		end
		if c.ring then
			c.ring.CFrame = CFrame.new(pos.X, ground + 0.1, pos.Z) * CFrame.Angles(0, 0, math.pi / 2)
		end
		if c.emitter then
			particles += c.emitter.Rate * CFG.GoldenLife
		end
		if c.shrinkT == nil and dist < nearestD then
			nearest, nearestD = c, dist
		end
	end
	-- quota de particules : traînées coupées au-delà
	local quota = Util.num(b.particleQuota and b.particleQuota.chase, 50, 0, 50)
	if particles > quota then
		for _, c in creatures do
			if c.emitter then
				c.emitter.Enabled = false
				particles -= c.emitter.Rate * CFG.GoldenLife
				if particles <= quota then
					break
				end
			end
		end
	end
	hlAcc += d
	if hlAcc >= CFG.RefreshHighlights then
		hlAcc = 0
		refreshHighlights(cam, b)
	end
	if nearest and nearestD <= CFG.GiggleRange and animT >= giggleAt then
		giggleAt = animT + CFG.GiggleMin + math.random() * (CFG.GiggleMax - CFG.GiggleMin)
		Util.safe("AudioController.play", nil, AudioController.play, "Giggle", 0.1)
	end
	if #bulkParts > 0 then
		local ok, err = pcall(function()
			workspace:BulkMoveTo(bulkParts, bulkCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end)
		if not ok then
			Util.raise("ChaseRenderer.bulk", tostring(err))
		end
	end
	local count, hl, models = 0, 0, 0
	local live = 0
	for _, c in creatures do
		count += 1
		if c.highlight then
			hl += 1
		end
		if c.handle then
			models += 1
		end
		if c.emitter and c.emitter.Enabled then
			live += c.emitter.Rate * CFG.GoldenLife
		end
	end
	lastStats = { creatures = count, highlights = hl, particles = live, models = models }
end

-- Création des états ; aucun yield long
function ChaseRenderer.Init()
	creatures = {}
end

-- Connexions et boucles
function ChaseRenderer.Start()
	if started then
		return
	end
	started = true
	table.insert(
		connections,
		WorldStateController.CreatureFinished:Connect(function(finish: Types.ChaseFinish)
			if type(finish) == "table" and type(finish.id) == "number" then
				startShrink(finish.id)
			end
		end)
	)
	table.insert(
		connections,
		RunService.RenderStepped:Connect(function(dt: number)
			Util.guard("ChaseRenderer.step", ChaseRenderer._step, dt)
		end)
	)
end

-- Position dessinée d'une créature
function ChaseRenderer.positionOf(id: number): Vector3?
	local c = if type(id) == "number" then creatures[id] else nil
	if c == nil or c.shrinkT ~= nil then
		return nil
	end
	return c.pos
end

-- Compteurs de budget (créatures, Highlight, particules)
function ChaseRenderer.stats(): { [string]: number }
	return table.clone(lastStats)
end

-- Coupe les connexions (fin de session, specs)
function ChaseRenderer._stop()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	started = false
end

return ChaseRenderer
