--!strict
-- Emotes (lot B5, étape 4 ; GDD v2.0 §6.5, Annexe B.3 « emotes » ; plan B5 V10, D21, D29) : les 6
-- emotes de la v2.0 dessinées en petits effets au-dessus de la tête du joueur, sur
-- WorldStateController.EmoteShown. Seulement : kind == 3 (croix ←, la seule qui porte une emote
-- choisie), un identifiant parmi splorch, wave, confettiCrown, bigPlopDance, hammerTap, hugEmote,
-- une charge v2.0 présente (au moins un interrupteur de World/Flags ouvert) et un joueur à 150 studs
-- au plus de mon personnage. Une emote de la v1.3 (wave des sortes 1 et 2, cheer, bravo…) ne dessine
-- rien ici ; aucun Humanoid:PlayEmote (R4).
--   splorch      : une goutte qui gonfle puis éclate en 8 gouttes (VFXController.blobs) ;
--   wave         : 3 anneaux qui montent (« ola », VFXController.ring) ;
--   confettiCrown: couronne de 8 confettis qui tourne au-dessus de la tête ;
--   bigPlopDance : un mini Big Plop d'1 stud qui fait 2 bonds sur la tête ;
--   hammerTap    : petit maillet, 3 coups (ChantierTap, repli Click) ;
--   hugEmote     : 2 cœurs qui se rejoignent puis une petite gerbe rose.
-- 2,5 s au plus chacune ; une emote par joueur (la nouvelle remplace l'ancienne) ; 6 à la fois au
-- plus ; pièces en réserve (48 au plus), particules par VFXController (quota des effets).
--   Emotes.start(fx) / Emotes.stop() / Emotes._step(dt) / Emotes.stats() / Emotes._state()
--   Emotes._configure(sources)   -- specs : son
-- Interrupteurs coupés : aucune instance, aucune boucle par image ; une écoute de signal.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Sounds = require(Shared.Config.Sounds)

local Client = script.Parent.Parent
local Flags = require(Client.World.Flags)
local Util = require(Client.World.Util)
local AudioController = require(Client.Controllers.AudioController)
local WorldStateController = require(Client.Controllers.WorldStateController)

local Emotes = {}

Emotes.IDS = table.freeze({ "splorch", "wave", "confettiCrown", "bigPlopDance", "hammerTap", "hugEmote" })
local KNOWN: { [string]: number } = {} -- durée de chaque emote (s)
local DURATION = {
	splorch = 1.6,
	wave = 1.2,
	confettiCrown = 2.5,
	bigPlopDance = 1.4,
	hammerTap = 1.6,
	hugEmote = 1.4,
}
for _, id in Emotes.IDS do
	KNOWN[id] = (DURATION :: any)[id]
end
Emotes.MAX_TIME = 2.5
Emotes.RANGE = 150 -- studs
local KIND = 3 -- croix ← (Cosmetics : emote choisie dans les Réglages)
local MAX_LIVE = 6
local POOL_MAX = 48
local HEAD = 3.2 -- studs au-dessus de HumanoidRootPart
local PINK = Color3.fromRGB(255, 150, 200)
local RED = Color3.fromRGB(255, 90, 120)
local WOOD = Color3.fromRGB(150, 100, 60)
local DARK = Color3.fromRGB(40, 30, 40)
local CONFETTI = {
	Color3.fromRGB(255, 120, 180),
	Color3.fromRGB(255, 220, 90),
	Color3.fromRGB(120, 210, 255),
	Color3.fromRGB(150, 230, 170),
}

export type Fx = {
	burst: (Vector3, Color3, number) -> (),
	blobs: (Vector3, Color3, number) -> (),
	ring: (Vector3, Color3, number, number) -> (),
}

type Live = {
	userId: number,
	id: string,
	t: number,
	life: number,
	parts: { Part },
	marks: { [string]: boolean },
}

local fx: Fx? = nil
local started = false
local connections: { RBXScriptConnection } = {}
local stepConn: RBXScriptConnection? = nil
local live: { Live } = {}
local pool: { Part } = {}
local inUse = 0
local folder: Folder? = nil
local counters = { shown = 0, refused = 0, replaced = 0 }
local sources: { play: ((string) -> ())? } = {}

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
	local sub = (root :: Instance):FindFirstChild("Emotes")
	if sub == nil or not sub:IsA("Folder") then
		local created = Instance.new("Folder")
		created.Name = "Emotes"
		created.Parent = root
		sub = created
	end
	folder = sub :: Folder
	return sub :: Folder
end

local function takePart(shape: Enum.PartType, size: Vector3, color: Color3, neon: boolean): Part?
	if inUse >= POOL_MAX then
		return nil
	end
	local p = table.remove(pool)
	if p == nil then
		local created = Instance.new("Part")
		created.Name = "EmotePiece"
		created.Anchored = true
		created.CanCollide = false
		created.CanQuery = false
		created.CanTouch = false
		created.CastShadow = false
		p = created
	end
	local part = p :: Part
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	part.Transparency = 0
	part.Parent = clientFolder()
	inUse += 1
	return part
end

local function giveParts(e: Live)
	for _, p in e.parts do
		p.Parent = nil
		inUse -= 1
		if #pool < 16 then
			table.insert(pool, p)
		else
			p:Destroy()
		end
	end
	table.clear(e.parts)
end

local function playSound(name: string, fallback: string)
	local def: any = (Sounds :: any)[name]
	local key = if type(def) == "table" and type(def.id) == "string" and def.id ~= "" then name else fallback
	local fn = sources.play
	if fn then
		pcall(fn, key)
		return
	end
	Util.safe("AudioController.play", nil, AudioController.play, key)
end

local function anyFlag(): boolean
	for _, name in Flags.FLAGS do
		if Flags.on(name) then
			return true
		end
	end
	return false
end

local function headOf(userId: number): Vector3?
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position + Vector3.new(0, HEAD, 0)
	end
	return nil
end

-- Pièces propres à chaque emote (nil = aucune pièce : effets de VFXController seulement)
local function dress(e: Live): boolean
	local function add(shape: Enum.PartType, size: Vector3, color: Color3, neon: boolean): boolean
		local p = takePart(shape, size, color, neon)
		if p == nil then
			return false
		end
		table.insert(e.parts, p)
		return true
	end
	local ok = true
	if e.id == "splorch" then
		ok = add(Enum.PartType.Ball, Vector3.new(0.4, 0.4, 0.4), PINK, false)
	elseif e.id == "confettiCrown" then
		for i = 1, 8 do
			ok = ok and add(Enum.PartType.Block, Vector3.new(0.3, 0.3, 0.08), CONFETTI[(i - 1) % 4 + 1], true)
		end
	elseif e.id == "bigPlopDance" then
		ok = add(Enum.PartType.Ball, Vector3.new(1, 1, 1), PINK, false)
			and add(Enum.PartType.Ball, Vector3.new(0.18, 0.18, 0.18), DARK, false)
			and add(Enum.PartType.Ball, Vector3.new(0.18, 0.18, 0.18), DARK, false)
	elseif e.id == "hammerTap" then
		ok = add(Enum.PartType.Block, Vector3.new(0.15, 0.15, 1.1), WOOD, false)
			and add(Enum.PartType.Block, Vector3.new(0.5, 0.4, 0.4), WOOD, false)
	elseif e.id == "hugEmote" then
		ok = add(Enum.PartType.Ball, Vector3.new(0.5, 0.5, 0.5), RED, true)
			and add(Enum.PartType.Ball, Vector3.new(0.5, 0.5, 0.5), PINK, true)
	end
	if not ok then
		giveParts(e)
	end
	return ok
end

local function once(e: Live, key: string, at: number): boolean
	if e.marks[key] or e.t < at then
		return false
	end
	e.marks[key] = true
	return true
end

-- Une image d'une emote ; faux quand elle est finie
local function stepOne(e: Live, dt: number): boolean
	e.t += dt
	local head = headOf(e.userId)
	if head == nil or e.t >= e.life or e.t >= Emotes.MAX_TIME then
		return false
	end
	local f = fx
	local t = e.t
	local parts = e.parts
	if e.id == "splorch" then
		if t < 0.8 then
			local s = 0.4 + t / 0.8
			parts[1].Size = Vector3.new(s, s, s)
			parts[1].CFrame = CFrame.new(head + Vector3.new(0, 0.5, 0))
		elseif once(e, "pop", 0.8) then
			parts[1].Transparency = 1
			if f then
				pcall(f.blobs, head + Vector3.new(0, 0.5, 0), PINK, 8)
			end
		end
	elseif e.id == "wave" then
		for i = 1, 3 do
			if once(e, "ring" .. i, (i - 1) * 0.3) and f then
				pcall(f.ring, head + Vector3.new(0, (i - 1) * 0.6, 0), CONFETTI[i], 3 + i, 0.5)
			end
		end
	elseif e.id == "confettiCrown" then
		for i, p in parts do
			local a = t * 3 + i * math.pi / 4
			p.CFrame = CFrame.new(
				head + Vector3.new(math.cos(a) * 1.2, 0.4 + 0.15 * math.sin(t * 6 + i), math.sin(a) * 1.2)
			) * CFrame.Angles(0, -a, 0)
		end
	elseif e.id == "bigPlopDance" then
		local k = (t % 0.6) / 0.6
		local hop = if t < 1.2 then math.sin(math.pi * k) * 1.2 else 0
		local body = head + Vector3.new(0, 0.5 + hop, 0)
		parts[1].CFrame = CFrame.new(body)
		parts[2].CFrame = CFrame.new(body + Vector3.new(-0.18, 0.1, -0.45))
		parts[3].CFrame = CFrame.new(body + Vector3.new(0.18, 0.1, -0.45))
	elseif e.id == "hammerTap" then
		local swing = 0
		for i, at in { 0.3, 0.8, 1.3 } do
			if t >= at - 0.2 and t < at then
				swing = (at - t) / 0.2
			end
			if once(e, "tap" .. i, at) then
				playSound("ChantierTap", "Click")
			end
		end
		local pivot = CFrame.new(head + Vector3.new(0.6, 0.3, 0)) * CFrame.Angles(swing * 1.2, 0, 0)
		parts[1].CFrame = pivot * CFrame.new(0, 0, -0.55)
		parts[2].CFrame = pivot * CFrame.new(0, 0, -1.1)
	elseif e.id == "hugEmote" then
		local k = math.min(1, t / 1)
		local gap = 1.5 * (1 - k)
		parts[1].CFrame = CFrame.new(head + Vector3.new(-gap, 0.4, 0))
		parts[2].CFrame = CFrame.new(head + Vector3.new(gap, 0.4, 0))
		if once(e, "meet", 1) and f then
			pcall(f.burst, head + Vector3.new(0, 0.4, 0), PINK, 6)
		end
	end
	return true
end

local refreshLoop: () -> ()

local function finish(i: number)
	local e = table.remove(live, i)
	if e then
		giveParts(e)
	end
end

local function onEmote(payload: any)
	if type(payload) ~= "table" or payload.kind ~= KIND then
		return
	end
	local id = payload.emote
	local life = if type(id) == "string" then KNOWN[id] else nil
	if life == nil or not anyFlag() then
		return
	end
	local userId = payload.userId
	if type(userId) ~= "number" or userId <= 0 or userId % 1 ~= 0 then
		return
	end
	local head = headOf(userId)
	local mine = Util.localRoot()
	if head == nil or mine == nil or (head - mine.Position).Magnitude > Emotes.RANGE then
		counters.refused += 1
		return
	end
	for i = #live, 1, -1 do
		if live[i].userId == userId then
			finish(i)
			counters.replaced += 1
		end
	end
	if #live >= MAX_LIVE then
		counters.refused += 1
		return
	end
	local e: Live = { userId = userId, id = id, t = 0, life = life, parts = {}, marks = {} }
	if not dress(e) then
		counters.refused += 1
		return
	end
	table.insert(live, e)
	counters.shown += 1
	stepOne(e, 0)
	refreshLoop()
end

function Emotes._step(dt: number)
	local d = Util.num(dt, 0, 0, 1)
	for i = #live, 1, -1 do
		local ok, keep = pcall(stepOne, live[i], d)
		if not ok then
			Util.raise("Emotes.step", tostring(keep))
			finish(i)
		elseif not keep then
			finish(i)
		end
	end
	refreshLoop()
end

function refreshLoop()
	if not started then
		return
	end
	local need = #live > 0
	if need and stepConn == nil then
		stepConn = RunService.RenderStepped:Connect(function(dt: number)
			Util.guard("Emotes.step", Emotes._step, dt)
		end)
	elseif not need and stepConn ~= nil then
		local c = stepConn :: RBXScriptConnection
		stepConn = nil
		c:Disconnect()
	end
end

function Emotes.start(effects: Fx)
	if started then
		return
	end
	started = true
	fx = effects
	table.insert(
		connections,
		WorldStateController.EmoteShown:Connect(function(payload: any)
			Util.guard("Emotes.shown", onEmote, payload)
		end) :: any
	)
end

function Emotes.stop()
	for i = #live, 1, -1 do
		finish(i)
	end
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	local c = stepConn
	stepConn = nil
	if c then
		c:Disconnect()
	end
	started = false
end

function Emotes.stats(): { [string]: number }
	return {
		shown = counters.shown,
		refused = counters.refused,
		replaced = counters.replaced,
		live = #live,
		parts = inUse,
		pooled = #pool,
		looping = if stepConn then 1 else 0,
		connections = #connections + (if stepConn then 1 else 0),
	}
end

function Emotes._state(): { { [string]: any } }
	local out = {}
	for _, e in live do
		table.insert(out, { userId = e.userId, id = e.id, t = e.t, parts = #e.parts })
	end
	return out
end

function Emotes._configure(options: any?)
	local o: any = if type(options) == "table" then options else {}
	sources.play = if type(o.play) == "function" then o.play else nil
end

return Emotes
