--!strict
-- Fete (lot B5, étape 5 ; GDD v2.0 §7.5 « Place en fête », §11.5 budgets ; docs/04 §27.5
-- EventState.fete ; plan B5 W2, D23, D29) : la place en fête, décor SEUL, dessiné par le client depuis
-- EventState.fete = { level } (0-5 ; interrupteur Fete du serveur : clé absente interrupteur coupé ;
-- points en mémoire du serveur, remis à 0 avec lui).
--
--   Fete.start(fx)             -- VFXController.Start : une écoute (WorldStateController.EventChanged)
--   Fete.stop()                -- coupe tout, rend chaque instance (fin, specs)
--   Fete.level()               -- niveau dessiné (0-5)
--   Fete.footprints()          -- emprises de chaque pièce (repère du monde ; specs)
--   Fete.stats() / _state() / _configure(sources) / _step(dt) / _refresh()   -- specs, Diagnostics
--
-- Niveaux CUMULÉS (chaque niveau garde le décor des précédents), construits une fois par changement :
--   1 guirlandes : 8 pièces Neon entre les lampadaires de l'anneau de la place, à 8,6 studs ;
--   2 ballons : 4 ballons et leurs 4 ficelles sur la scène (plaza « stage ») ;
--   3 arches : 2 arches de 5 pièces sur les bouches des rues nord et sud, piliers hors de la rue ;
--   4 petits feux d'artifice : une gerbe toutes les 6 s au-dessus de la place (quota des effets de
--     VFXController, 0 pièce ; la seule boucle par image de ce module) ;
--   5 statue dorée de Big Plop (7 pièces) à côté de la statue de la place.
-- Positions calculées depuis WorldLayout.plaza(...) et les lampadaires de Render/WorldDecor, jamais
-- écrites en dur ; chaque pièce porte l'attribut Footprint (nom de son emprise) et son emprise couvre
-- son dessin réel (spec). Système « fete » de Render/VisualBudget : 40 pièces, 20 particules (ligne
-- NOUVELLE du tableau du GDD §11.5, journal B5).
-- Un niveau qui MONTE pendant la partie : Toast « Place en fête : niveau n » et son FeteLevel (repli
-- LevelUp) ; jamais au chargement, rien quand le niveau baisse (nouveau serveur : retour à 0).
-- Aucune écriture de Lighting. Interrupteurs coupés : aucune instance, aucune boucle, une écoute.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Sounds = require(Shared.Config.Sounds)
local WorldLayout = require(Shared.Logic.WorldLayout)
local WorldDecor = require(Shared.Render.WorldDecor)

local Client = script.Parent.Parent
local Util = require(Client.World.Util)
local AudioController = require(Client.Controllers.AudioController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local VisualBudget = require(Client.Render.VisualBudget)

local Fete = {}

export type Footprint = {
	name: string,
	level: number,
	x: number,
	z: number,
	r: number, -- disque horizontal qui contient le dessin
	bottom: number,
	top: number,
}
type Fx = { burst: ((Vector3, Color3, number) -> ())? }
type Spec = {
	footprint: string,
	shape: Enum.PartType,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
}

local SYSTEM = "fete"
local LIMITS = table.freeze({ parts = 40, particles = 20, lights = 0 })
local MAX_LEVEL = 5
local FIREWORK_EVERY = 6 -- s
local FIREWORK_COUNT = 20
local FIREWORK_HEIGHT = { 28, 36 }
local FIREWORK_RADIUS = { 8, 34 }
-- dimensions (studs)
local GARLAND_HEIGHT = WorldDecor.Lamp.poleHeight - 0.4
local GARLAND_THICK = 0.35
local LAMP_RING_MAX = WorldLayout.Const.PlazaRadius + 6 -- lampadaires de l'anneau de la place
local BALLOON_D = 2.4
local BALLOON_STRING = 0.12
local BALLOON_OFFSETS: { Vector3 } = table.freeze({
	Vector3.new(1.6, 12, 0.6),
	Vector3.new(-1.2, 13.4, 1.4),
	Vector3.new(-0.8, 11.2, -1.6),
	Vector3.new(1.0, 14.2, -0.8),
})
local STRING_FOOT = 1.2 -- pied des ficelles : posé sur le disque de la scène
local BALLOON_RADIUS = 3.5 -- emprise du bouquet (≥ décalage 1,8 + rayon 1,2 + marge)
local ARCH_FROM_EDGE = 8 -- studs au-delà du bord de la place (bouche de la rue)
local STREET_HALF = 5 -- demi-largeur des rues radiales (Server/World/Town : 10 studs)
local PILLAR_SIDE = STREET_HALF + 1.5 -- axe d'un pilier depuis l'axe de la rue
local PILLAR_W = 0.8
local PILLAR_H = 9
local BEAM_H = 0.9
local ARCH_BALL = 1.4
local STATUE_OFFSET = Vector3.new(-9, 0, 2) -- depuis la statue de la place (socle Ø 10)
local STATUE_RADIUS = 2.4 -- emprise de la statue dorée (plinthe Ø 4,4)
local STATUE_TOP = 6
local GOLD = Color3.fromRGB(255, 200, 60)
local DARK = Color3.fromRGB(60, 40, 30)
local GEM = Color3.fromRGB(255, 120, 180)
local COLORS: { Color3 } = table.freeze({
	Color3.fromRGB(255, 120, 180),
	Color3.fromRGB(255, 220, 90),
	Color3.fromRGB(130, 230, 190),
	Color3.fromRGB(120, 190, 255),
})
local ARCH_COLOR = Color3.fromRGB(255, 170, 210)

local sources: { play: ((string) -> ())?, toast: ((string) -> ())? } = {}
local fx: Fx = {}
local started = false
local connections: { RBXScriptConnection } = {}
local stepConn: RBXScriptConnection? = nil
local root: Folder? = nil
local tiers: { [number]: { parts: { BasePart }, folder: Folder } } = {}
local drawn = 0 -- niveau dessiné
local armed = false
local fireT = 0
local fireworksTaken = false
local rng = Random.new(7112026)
local counters = { builds = 0, toasts = 0, bursts = 0, refused = 0 }

-- =============================================================================================
-- Plan (pur) : pièces et emprises de chaque niveau
-- =============================================================================================

local function vertical(at: Vector3): CFrame
	return CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2)
end

-- Lampadaires de l'anneau de la place, triés par angle
local function plazaLamps(): { Vector3 }
	local center = WorldLayout.plaza("center")
	local out: { Vector3 } = {}
	for _, lamp in WorldDecor.lamps() do
		local d = Vector3.new(lamp.position.X - center.X, 0, lamp.position.Z - center.Z)
		if d.Magnitude <= LAMP_RING_MAX then
			table.insert(out, lamp.position)
		end
	end
	table.sort(out, function(a, b)
		return math.atan2(a.Z - center.Z, a.X - center.X) < math.atan2(b.Z - center.Z, b.X - center.X)
	end)
	return out
end

local PLAN: { [number]: { Spec } } = {}
local FOOTPRINTS: { Footprint } = {}

local function addFoot(name: string, level: number, at: Vector3, r: number, bottom: number, top: number)
	table.insert(
		FOOTPRINTS,
		{ name = name, level = level, x = at.X, z = at.Z, r = r, bottom = bottom, top = top }
	)
end

do
	for level = 1, MAX_LEVEL do
		PLAN[level] = {}
	end
	-- 1 guirlandes entre deux lampadaires voisins de l'anneau
	local lamps = plazaLamps()
	for i = 1, #lamps do
		local a = lamps[i]
		local b = lamps[i % #lamps + 1]
		local pa = Vector3.new(a.X, GARLAND_HEIGHT, a.Z)
		local pb = Vector3.new(b.X, GARLAND_HEIGHT, b.Z)
		local mid = (pa + pb) / 2
		local length = (pb - pa).Magnitude
		local name = "garland" .. i
		table.insert(PLAN[1], {
			footprint = name,
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(length, GARLAND_THICK, GARLAND_THICK),
			cf = CFrame.lookAt(mid, pb) * CFrame.Angles(0, math.pi / 2, 0),
			color = COLORS[(i - 1) % #COLORS + 1],
			material = Enum.Material.Neon,
		})
		addFoot(
			name,
			1,
			mid,
			length / 2 + GARLAND_THICK,
			GARLAND_HEIGHT - GARLAND_THICK,
			GARLAND_HEIGHT + GARLAND_THICK
		)
	end
	-- 2 ballons sur la scène
	local stage = WorldLayout.plaza("stage")
	for i, off in BALLOON_OFFSETS do
		local top = stage + off
		local foot = Vector3.new(stage.X + off.X * 0.4, STRING_FOOT, stage.Z + off.Z * 0.4)
		local low = top - Vector3.new(0, BALLOON_D / 2, 0)
		local length = (low - foot).Magnitude
		table.insert(PLAN[2], {
			footprint = "balloons",
			shape = Enum.PartType.Ball,
			size = Vector3.new(BALLOON_D, BALLOON_D, BALLOON_D),
			cf = CFrame.new(top),
			color = COLORS[(i - 1) % #COLORS + 1],
			material = Enum.Material.SmoothPlastic,
		})
		table.insert(PLAN[2], {
			footprint = "balloons",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(length, BALLOON_STRING, BALLOON_STRING),
			cf = CFrame.lookAt((foot + low) / 2, low) * CFrame.Angles(0, math.pi / 2, 0),
			color = Color3.fromRGB(250, 250, 250),
			material = Enum.Material.SmoothPlastic,
		})
	end
	addFoot(
		"balloons",
		2,
		stage,
		BALLOON_RADIUS,
		STRING_FOOT - BALLOON_STRING,
		stage.Y + 14.2 + BALLOON_D / 2 + 0.1
	)
	-- 3 arches sur les bouches des rues nord (− Z) et sud (+ Z)
	local center = WorldLayout.plaza("center")
	for k, dir in { Vector3.new(0, 0, -1), Vector3.new(0, 0, 1) } do
		local at = center + dir * (WorldLayout.Const.PlazaRadius + ARCH_FROM_EDGE)
		local side = Vector3.new(-dir.Z, 0, dir.X) -- perpendiculaire à la rue
		local name = "arch" .. k
		for s, sign in { -1, 1 } do
			local p = at + side * (sign * PILLAR_SIDE)
			local pname = name .. (if s == 1 then "L" else "R")
			table.insert(PLAN[3], {
				footprint = pname,
				shape = Enum.PartType.Block,
				size = Vector3.new(PILLAR_W, PILLAR_H, PILLAR_W),
				cf = CFrame.new(p + Vector3.new(0, PILLAR_H / 2, 0)),
				color = Color3.fromRGB(255, 250, 245),
				material = Enum.Material.SmoothPlastic,
			})
			addFoot(pname, 3, p, PILLAR_W * 0.75, 0, PILLAR_H)
			table.insert(PLAN[3], {
				footprint = name,
				shape = Enum.PartType.Ball,
				size = Vector3.new(ARCH_BALL, ARCH_BALL, ARCH_BALL),
				cf = CFrame.new(p + Vector3.new(0, PILLAR_H + BEAM_H + ARCH_BALL / 2, 0)),
				color = COLORS[(k + s) % #COLORS + 1],
				material = Enum.Material.Neon,
			})
		end
		local beamAt = at + Vector3.new(0, PILLAR_H + BEAM_H / 2, 0)
		table.insert(PLAN[3], {
			footprint = name,
			shape = Enum.PartType.Block,
			size = Vector3.new(2 * PILLAR_SIDE + PILLAR_W, BEAM_H, BEAM_H),
			cf = CFrame.lookAt(beamAt, beamAt + side) * CFrame.Angles(0, math.pi / 2, 0),
			color = ARCH_COLOR,
			material = Enum.Material.SmoothPlastic,
		})
		addFoot(name, 3, at, PILLAR_SIDE + PILLAR_W + 0.2, PILLAR_H, PILLAR_H + BEAM_H + ARCH_BALL + 0.1)
	end
	-- 5 statue dorée de Big Plop à côté de la statue de la place
	local base = WorldLayout.plaza("statue") + STATUE_OFFSET
	local face = (center - base)
	local look = Vector3.new(face.X, 0, face.Z).Unit
	local right = Vector3.new(-look.Z, 0, look.X)
	local function piece(
		shape: Enum.PartType,
		size: Vector3,
		cf: CFrame,
		color: Color3,
		material: Enum.Material
	)
		table.insert(PLAN[5], {
			footprint = "statue",
			shape = shape,
			size = size,
			cf = cf,
			color = color,
			material = material,
		})
	end
	piece(
		Enum.PartType.Cylinder,
		Vector3.new(1.2, 4.4, 4.4),
		vertical(base + Vector3.new(0, 0.6, 0)),
		GOLD,
		Enum.Material.Marble
	)
	piece(
		Enum.PartType.Cylinder,
		Vector3.new(0.2, 4.6, 4.6),
		vertical(base + Vector3.new(0, 1.3, 0)),
		GOLD,
		Enum.Material.Neon
	)
	local body = base + Vector3.new(0, 1.4 + 1.7, 0)
	piece(Enum.PartType.Ball, Vector3.new(3.4, 3.4, 3.4), CFrame.new(body), GOLD, Enum.Material.Foil)
	for _, sign in { -1, 1 } do
		local eye = body + look * 1.55 + right * (sign * 0.55) + Vector3.new(0, 0.35, 0)
		piece(
			Enum.PartType.Ball,
			Vector3.new(0.45, 0.45, 0.45),
			CFrame.new(eye),
			DARK,
			Enum.Material.SmoothPlastic
		)
	end
	local crown = body + Vector3.new(0, 1.85, 0)
	piece(Enum.PartType.Cylinder, Vector3.new(0.7, 1.6, 1.6), vertical(crown), GOLD, Enum.Material.Neon)
	piece(
		Enum.PartType.Ball,
		Vector3.new(0.5, 0.5, 0.5),
		CFrame.new(crown + Vector3.new(0, 0.55, 0)),
		GEM,
		Enum.Material.Neon
	)
	addFoot("statue", 5, base, STATUE_RADIUS, 0, STATUE_TOP)
end

-- =============================================================================================
-- Outils
-- =============================================================================================

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

local function say(text: string)
	local custom = sources.toast
	if custom then
		pcall(custom, text)
		return
	end
	local ok, toast = pcall(function(): any
		return require(Client.UI.Toast) :: any
	end)
	if ok and type(toast) == "table" and type(toast.message) == "function" then
		pcall(toast.message, text, "reward")
	end
end

local function clientWorld(): Instance
	local r = workspace:FindFirstChild("ClientWorld")
	if r == nil then
		local created = Instance.new("Folder")
		created.Name = "ClientWorld"
		created.Parent = workspace
		r = created
	end
	return r :: Instance
end

local function rootFolder(): Folder
	local f = root
	if f and f.Parent ~= nil then
		return f
	end
	local created = Instance.new("Folder")
	created.Name = "Fete"
	created.Parent = clientWorld()
	root = created
	return created
end

-- =============================================================================================
-- Construction par niveau
-- =============================================================================================

local function buildTier(level: number)
	local plan = PLAN[level]
	if tiers[level] ~= nil or plan == nil then
		return
	end
	if #plan > 0 and not VisualBudget.take(SYSTEM, #plan) then
		counters.refused += 1
		return
	end
	local f = Instance.new("Folder")
	f.Name = "Level" .. level
	local parts: { BasePart } = {}
	for i, s in plan do
		local p = Instance.new("Part")
		p.Name = s.footprint .. "_" .. i
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Shape = s.shape
		p.Size = s.size
		p.CFrame = s.cf
		p.Color = s.color
		p.Material = s.material
		p:SetAttribute("Footprint", s.footprint)
		p.Parent = f
		table.insert(parts, p)
	end
	f.Parent = rootFolder()
	tiers[level] = { parts = parts, folder = f }
	counters.builds += 1
end

local function removeTier(level: number)
	local t = tiers[level]
	if t == nil then
		return
	end
	tiers[level] = nil
	t.folder:Destroy()
	if #t.parts > 0 then
		VisualBudget.release(SYSTEM, #t.parts)
	end
end

local function stopFireworks()
	local c = stepConn
	stepConn = nil
	if c then
		c:Disconnect()
	end
	if fireworksTaken then
		fireworksTaken = false
		VisualBudget.release(SYSTEM, LIMITS.particles, "particles")
	end
end

local function startFireworks()
	if stepConn ~= nil then
		return
	end
	fireworksTaken = VisualBudget.take(SYSTEM, LIMITS.particles, "particles")
	fireT = 0
	stepConn = RunService.RenderStepped:Connect(function(dt: number)
		Util.guard("Fete.step", Fete._step, dt)
	end)
end

-- Dessine le niveau `level` (cumulé) : ajoute les niveaux qui manquent, retire ceux au-dessus
local function setLevel(level: number)
	if level > 0 then
		VisualBudget.declare(SYSTEM, LIMITS)
	end
	for l = MAX_LEVEL, level + 1, -1 do
		removeTier(l)
	end
	for l = 1, level do
		buildTier(l)
	end
	if level >= 4 then
		startFireworks()
	else
		stopFireworks()
	end
	if level == 0 then
		local f = root
		root = nil
		if f then
			f:Destroy()
		end
	end
	drawn = level
end

local function readLevel(): number
	local ev: any = Util.safe("WorldStateController.event", nil, WorldStateController.event)
	local fete = if type(ev) == "table" then ev.fete else nil
	if type(fete) ~= "table" then
		return 0
	end
	return math.floor(Util.num(fete.level, 0, 0, MAX_LEVEL))
end

local function evaluate()
	-- relecture B5 (journal B5-63) : tant qu'aucun EventState n'est arrivé (le client démarre avant que
	-- le serveur ait chargé le profil), rien n'est « vu » : le premier état reçu reste le chargement
	if type(Util.safe("WorldStateController.event", nil, WorldStateController.event)) ~= "table" then
		return
	end
	local level = readLevel()
	local first = not armed
	armed = true
	if level == drawn then
		return
	end
	local before = drawn
	setLevel(level)
	-- annonce seulement quand le niveau MONTE pendant la partie
	if not first and level > before then
		counters.toasts += 1
		say(Util.t("fete.level", { n = level }))
		playSound("FeteLevel", "LevelUp")
	end
end

-- Une image (seulement au niveau 4 et plus) : une gerbe toutes les 6 s au-dessus de la place
function Fete._step(dt: number)
	if drawn < 4 then
		stopFireworks()
		return
	end
	fireT += Util.num(dt, 0, 0, 1)
	if fireT < FIREWORK_EVERY then
		return
	end
	fireT = 0
	local burst = fx.burst
	if burst == nil then
		return
	end
	local center = WorldLayout.plaza("center")
	local a = rng:NextNumber(0, 2 * math.pi)
	local r = rng:NextNumber(FIREWORK_RADIUS[1], FIREWORK_RADIUS[2])
	local pos = center
		+ Vector3.new(
			r * math.cos(a),
			rng:NextNumber(FIREWORK_HEIGHT[1], FIREWORK_HEIGHT[2]),
			r * math.sin(a)
		)
	counters.bursts += 1
	pcall(burst, pos, COLORS[rng:NextInteger(1, #COLORS)], FIREWORK_COUNT)
end

-- =============================================================================================
-- Cycle de vie
-- =============================================================================================

function Fete.start(effects: Fx?)
	if started then
		return
	end
	started = true
	armed = false
	fx = if type(effects) == "table" then effects else {}
	table.insert(
		connections,
		WorldStateController.EventChanged:Connect(function()
			Util.guard("Fete.event", evaluate)
		end) :: any
	)
	evaluate()
end

function Fete.stop()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	setLevel(0)
	started = false
end

function Fete.level(): number
	return drawn
end

-- Emprises de chaque pièce (repère du monde) : disque horizontal x, z, r de bottom à top
function Fete.footprints(): { Footprint }
	local out = {}
	for i, f in FOOTPRINTS do
		out[i] = table.clone(f)
	end
	return out
end

function Fete._refresh()
	evaluate()
end

function Fete.stats(): { [string]: number }
	local parts = 0
	for _, t in tiers do
		parts += #t.parts
	end
	return {
		level = drawn,
		parts = parts,
		looping = if stepConn then 1 else 0,
		connections = #connections + (if stepConn then 1 else 0),
		builds = counters.builds,
		toasts = counters.toasts,
		bursts = counters.bursts,
		refused = counters.refused,
	}
end

function Fete._state(): { [string]: any }
	local out: { [number]: { BasePart } } = {}
	for l, t in tiers do
		out[l] = table.clone(t.parts)
	end
	return { level = drawn, tiers = out, folder = root }
end

-- Nombre de pièces de chaque niveau (plan ; specs)
function Fete.planCount(level: number): number
	local plan = PLAN[level]
	return if plan then #plan else 0
end

function Fete._configure(options: any?)
	local o: any = if type(options) == "table" then options else {}
	sources.play = if type(o.play) == "function" then o.play else nil
	sources.toast = if type(o.toast) == "function" then o.toast else nil
end

return Fete
