--!strict
-- Halo (lot B4, étape 5 ; GDD v2.0 §4.27, §11.5 ; décision D16 du plan B4). De 1 à 5 gouttes de gelée qui
-- tournent autour de la tête du propriétaire d'un ranch qui porte HaloOn = true [RanchSkins] et
-- Ascend ≥ 1 [JellyAscend] (RanchRenderer lit les attributs et appelle sync toutes les 0,5 s) :
--   * min(A, 5) gouttes aux couleurs de Visuals.Halo (menthe, ciel, lilas, or, arc-en-ciel : le NOMBRE
--     porte l'information, lisible sans les couleurs) ; au plus 5 pièces par joueur, budget visuel
--     « halo » (16 × 5) ; seulement pour un personnage à 150 studs au plus de la caméra (la plaque du
--     titre, qui montre la goutte dessinée et le nombre, a la même portée) ;
--   * placées à 15 Hz au plus par un seul workspace:BulkMoveTo ; la goutte arc-en-ciel change de couleur
--     2 fois par seconde (≤ 3, GDD §11.5) ; Mouvement réduit : immobiles autour de la tête (elles la
--     suivent sans tourner) et couleur fixe ;
--   * sans personnage, sans tête ou hors de portée : rien, sans trace ; interrupteurs coupés (aucun
--     attribut) : aucune instance et aucun travail par image (Halo.on reste faux : un test par image).
-- Pièces ancrées, CanCollide = CanQuery = CanTouch = false, CastShadow = false, Transparency 0, Neon ;
-- aucune lumière. Jamais d'erreur.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Visuals = require(Shared.Config.Visuals)
local RanchLook = require(Shared.Logic.RanchLook)

local Client = script.Parent.Parent
local Prefs = require(Client.Util.Prefs)
local Util = require(Client.World.Util)
local VisualBudget = require(script.Parent.VisualBudget)

local Halo = {}

-- Au moins un halo dessiné : RanchRenderer n'appelle step que si vrai
Halo.on = false

local MAX_DROPS = #Visuals.Halo
local RANGE = 150 -- studs (portée de la plaque du titre)
local HZ = 15
local RADIUS = 1.7 -- studs autour de l'axe de la tête
local HEIGHT = 1.6 -- studs au-dessus du centre de la tête
local TURN = 4 -- s par tour
local DROP = Vector3.new(0.6, 0.6, 0.6)
local RAINBOW_HZ = 2 -- changements de couleur par seconde de la goutte arc-en-ciel

local COLORS: { [string]: Color3 } = {
	mint = Color3.fromRGB(150, 240, 210),
	sky = Color3.fromRGB(140, 210, 255),
	lilac = Color3.fromRGB(200, 168, 255),
	gold = Color3.fromRGB(255, 204, 84),
	rainbow = Color3.fromRGB(255, 110, 120),
}
local RAINBOW = {
	Color3.fromRGB(255, 110, 120),
	Color3.fromRGB(255, 170, 90),
	Color3.fromRGB(255, 230, 110),
	Color3.fromRGB(140, 230, 140),
	Color3.fromRGB(120, 200, 255),
	Color3.fromRGB(150, 140, 255),
	Color3.fromRGB(210, 140, 255),
}

type Entry = { character: Model, head: BasePart, drops: { BasePart }, rainbow: number }

local entries: { [number]: Entry } = {}
local folder: Folder? = nil
local declared = false
local acc = 0
local clock = 0
local bulkParts: { BasePart } = {}
local bulkCFrames: { CFrame } = {}
local counters = { created = 0, destroyed = 0, writes = 0 }

local function reducedMotion(): boolean
	return Util.safe("Prefs.reducedMotion", false, Prefs.reducedMotion)
end

local function holder(): Folder
	local f = folder
	if f and f.Parent ~= nil then
		return f
	end
	local world = workspace:FindFirstChild("ClientWorld")
	if world == nil then
		local created = Instance.new("Folder")
		created.Name = "ClientWorld"
		created.Parent = workspace
		world = created
	end
	local made = Instance.new("Folder")
	made.Name = "Halos"
	made.Parent = world
	folder = made
	return made
end

local function prune()
	local f = folder
	if f and next(entries) == nil then
		f:Destroy()
		folder = nil
	end
	Halo.on = next(entries) ~= nil
end

local function release(slot: number)
	local e = entries[slot]
	if e == nil then
		return
	end
	for _, part in e.drops do
		part:Destroy()
		counters.destroyed += 1
	end
	VisualBudget.release("halo", #e.drops)
	entries[slot] = nil
end

-- Repère de la goutte i sur n autour de la tête à l'instant t (immobile en Mouvement réduit)
local function dropCFrame(head: BasePart, i: number, n: number, t: number, still: boolean): CFrame
	local turn = if still then 0 else 2 * math.pi * t / TURN
	local a = 2 * math.pi * (i - 1) / n + turn
	local p = head.Position
	return CFrame.new(p.X + RADIUS * math.cos(a), p.Y + HEIGHT, p.Z + RADIUS * math.sin(a))
end

local function newDrop(i: number, n: number, head: BasePart, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = "Drop" .. i
	part.Shape = Enum.PartType.Ball
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 0
	part.Material = Enum.Material.Neon
	part.Color = COLORS[Visuals.Halo[i]] or COLORS.mint
	part.Size = DROP
	part.CFrame = dropCFrame(head, i, n, clock, true)
	part.Parent = parent
	counters.created += 1
	return part
end

-- Halo du propriétaire du ranch `slot` : `character` (nil : aucun), `ascend` = A montré (0 : aucun
-- halo), `camera` = position de la caméra (portée) ; idempotent (même état : rien de créé ni d'écrit)
function Halo.sync(slot: number, character: Model?, ascend: number, camera: Vector3?)
	if type(slot) ~= "number" then
		return
	end
	local n = RanchLook.halo(ascend, true)
	local head = if character then character:FindFirstChild("Head") else nil
	local ok = n > 0 and head ~= nil and head:IsA("BasePart") and character ~= nil and character.Parent ~= nil
	if ok and camera ~= nil and ((head :: BasePart).Position - camera).Magnitude > RANGE then
		ok = false
	end
	local e = entries[slot]
	if not ok then
		if e then
			release(slot)
			prune()
		end
		return
	end
	local h = head :: BasePart
	if e and (e.character ~= character or e.head ~= h or #e.drops ~= n or e.drops[1].Parent == nil) then
		release(slot)
		e = nil
	end
	if e == nil then
		if not declared then
			declared = true
			VisualBudget.declare("halo", (VisualBudget.LIMITS :: any).halo)
		end
		if not VisualBudget.take("halo", n) then
			prune()
			return
		end
		local parent = holder()
		local drops: { BasePart } = {}
		for i = 1, n do
			drops[i] = newDrop(i, n, h, parent)
		end
		entries[slot] = { character = character :: Model, head = h, drops = drops, rainbow = 0 }
	end
	Halo.on = true
end

-- Retire le halo d'un ranch (ranch libéré, joueur parti)
function Halo.clear(slot: number)
	release(slot)
	prune()
end

-- Une image (seulement tant que Halo.on) : gouttes placées à 15 Hz au plus
function Halo.step(dt: number)
	local d = if type(dt) == "number" and dt == dt and dt > 0 then math.min(dt, 1) else 0
	clock += d
	acc += d
	if acc < 1 / HZ then
		return
	end
	acc = 0
	local still = reducedMotion()
	table.clear(bulkParts)
	table.clear(bulkCFrames)
	local writes = 0
	for slot, e in entries do
		if e.head.Parent == nil or e.drops[1].Parent == nil then
			release(slot)
		else
			local n = #e.drops
			for i, part in e.drops do
				table.insert(bulkParts, part)
				table.insert(bulkCFrames, dropCFrame(e.head, i, n, clock, still))
				writes += 1
			end
			if n >= MAX_DROPS then
				-- goutte arc-en-ciel : 2 changements de couleur par seconde, fixe en Mouvement réduit
				local idx = if still then 1 else (math.floor(clock * RAINBOW_HZ) % #RAINBOW) + 1
				if idx ~= e.rainbow then
					e.rainbow = idx
					e.drops[MAX_DROPS].Color = RAINBOW[idx]
					writes += 1
				end
			end
		end
	end
	if #bulkParts > 0 then
		local ok, err = pcall(function()
			workspace:BulkMoveTo(bulkParts, bulkCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end)
		if not ok then
			Util.raise("Halo.bulk", tostring(err))
		end
	end
	counters.writes = writes
	prune()
end

-- Gouttes dessinées par ranch et compteurs (specs, Diagnostics)
function Halo.stats(): { [string]: any }
	local drops: { [number]: number } = {}
	local total = 0
	for slot, e in entries do
		drops[slot] = #e.drops
		total += #e.drops
	end
	return {
		drops = drops,
		total = total,
		created = counters.created,
		destroyed = counters.destroyed,
		writes = counters.writes,
	}
end

-- Gouttes du halo d'un ranch (specs)
function Halo.drops(slot: number): { BasePart }
	local e = entries[slot]
	return if e then table.clone(e.drops) else {}
end

-- Tout retirer (fin de RanchRenderer, specs)
function Halo.stop()
	for slot in entries do
		release(slot)
	end
	prune()
	declared = false
	acc = 0
	clock = 0
end

return Halo
