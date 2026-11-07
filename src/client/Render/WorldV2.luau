--!strict
-- WorldV2 (lot B4, étape 5 ; GDD v2.0 §11.1, §11.5 ; décisions D9, D10, D21, D22, D30 du plan B4). Décors du
-- monde v2.0 construits par le client sous ClientWorld/WorldV2, pour LightingController (seul appelant de
-- update, toutes les 0,5 s et à chaque EventState ; il pose aussi les étiquettes, mécanisme LabelKey) :
--   * Observatoire (24 pièces + faisceau, colline nord r ≈ 340, au-delà du mur du bord : inaccessible,
--     aucune invite) tant que MON ranch porte TapisTier [RanchTiers] ; faisceau Neon vers le premier ranch
--     dont AscendReady est vrai (le mien d'abord) ; pendant EventState.spectacle.current.kind == "ascend",
--     vers le ranch du héros ; sinon aucun faisceau ;
--   * kiosque de Big Plop (15 pièces rayées menthe, WorldLayout.plaza("kiosk")) tant que
--     PanelController.available("Upgrades") et qu'une ligne de l'Atelier n'est pas cachée (UpgradeView) ;
--     étiquette world.kiosk ; invite □ « Atelier » de PromptController (kioskOpen, INT-B4-KIOSK) ;
--   * Prairie v2 (32 pièces, WorldLayout.meadowCenter(true)) tant que MON ranch porte Monuments
--     [Monuments] : les pièces de la Prairie du serveur (Wobbleton/Meadow) sont cachées SUR CE CLIENT
--     (Transparency 1, valeur d'origine gardée et rendue telle quelle à la coupure) et leur étiquette aussi ;
--   * costume d'hiver (D30) : glaçons sucre d'orge sous la lisse haute de la clôture de devant du ranch
--     courant et de ses 2 voisins (12 pièces chacun) tant qu'Ambience est ouvert et que le costume d'hiver
--     est en cours (dans le décor du costume, ≤ 300 pièces avec le sucre glace et les guirlandes).
-- Budgets visuels : « world » (Observatoire + faisceau + kiosque = 40), « meadow » (40). Interrupteurs
-- coupés : rien n'est construit (aucune instance), update lit seulement quelques attributs. Pièces ancrées,
-- non solides, sans ombre, Transparency 0, aucune lumière ; jamais d'erreur.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Clock = require(Shared.Util.Clock)
local RanchLook = require(Shared.Logic.RanchLook)
local WorldLayout = require(Shared.Logic.WorldLayout)

local Client = script.Parent.Parent
local WorldStateController = require(Client.Controllers.WorldStateController)
local Util = require(Client.World.Util)
local VisualBudget = require(script.Parent.VisualBudget)
local RanchKit = require(script.Parent.RanchKit)

local WorldV2 = {}

export type Context = {
	ambience: boolean, -- EventState.features.ambience (pile du directeur d'ambiance affichée)
	winter: boolean, -- costume d'hiver en cours (LightingController.resolve)
	payload: any, -- EventState reçu (spectacle en cours)
	world: Instance?, -- workspace.Wobbleton
}
export type LabelAnchor = { part: BasePart, key: string, height: number }

local RANCHES = WorldLayout.Const.Ranches
local KIOSK_PARTS = 15
local OBSERVATORY_PARTS = 24 -- + 1 faisceau
local BEAM_WIDTH = 0.8
local BEAM_MAX = 2000 -- studs (taille de pièce bornée par le moteur à 2 048)
WorldV2.ICICLES_PER_RANCH = 12 -- glaçons au plus par ranch (D30)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local PALETTE: { [string]: Color3 } = {
	white = rgb(255, 252, 250),
	cream = rgb(255, 240, 220),
	mint = rgb(150, 240, 210),
	mintDeep = rgb(80, 210, 170),
	pink = rgb(255, 182, 214),
	jelly = rgb(255, 120, 180),
	lilac = rgb(200, 168, 255),
	lilacDeep = rgb(150, 120, 220),
	sky = rgb(140, 210, 255),
	lemon = rgb(255, 236, 140),
	gold = rgb(255, 204, 84),
	wood = rgb(190, 140, 100),
	stone = rgb(225, 215, 235),
	beam = rgb(255, 240, 170),
	grass = rgb(150, 215, 120),
	path = rgb(250, 230, 190),
	bush = rgb(110, 190, 110),
	sign = rgb(255, 214, 236),
	ice = rgb(235, 248, 255),
	cane = rgb(235, 80, 100),
}

-- Observatoire (repère : pied de la colline, −Z vers la place) : socle, tour rayée, balcon, coupole,
-- fente, lunette tournée vers la place, porte, marches, fenêtres Neon, étoile au sommet
local OBSERVATORY: { RanchKit.Row } = {
	{ "c", 0, 1, 0, 14, 2, 0, "stone" },
	{ "c", 0, 9, 0, 10, 14, 0, "lilac" },
	{ "c", 0, 4, 0, 10.3, 0.6, 0, "mint" },
	{ "c", 0, 7.5, 0, 10.3, 0.6, 0, "mint" },
	{ "c", 0, 11, 0, 10.3, 0.6, 0, "mint" },
	{ "c", 0, 14.4, 0, 10.3, 0.6, 0, "mint" },
	{ "c", 0, 16.4, 0, 12.6, 0.8, 0, "pink" },
	{ "s", 0, 17.2, 0, 10, 0, 0, "sky" },
	{ "b", 0, 20.4, 0, 1.2, 3.2, 9.6, "lilacDeep" },
	{ "x", 0, 21.2, -3.4, 7, 1.6, 0, "white", nil, 0, 90, 30 },
	{ "s", 0, 23.0, -6.4, 1.9, 0, 0, "lemon", "n" },
	{ "b", 0, 4, -5.05, 2.6, 4, 0.4, "wood" },
	{ "b", 0, 0.25, -7.4, 4, 0.5, 1.2, "stone" },
	{ "b", 0, 0.75, -6.6, 4, 0.5, 1.2, "stone" },
	{ "b", 0, 1.25, -5.8, 4, 0.5, 1.2, "stone" },
	{ "b", -3.0, 9.5, -4.2, 1.1, 1.6, 0.3, "lemon", "n", 0, -35, 0 },
	{ "b", 3.0, 9.5, -4.2, 1.1, 1.6, 0.3, "lemon", "n", 0, 35, 0 },
	{ "b", 0, 12.6, -5.05, 1.2, 1.6, 0.3, "lemon", "n" },
	{ "b", 0, 7.2, -5.05, 1.2, 1.2, 0.3, "lemon", "n" },
	{ "s", 0, 22.6, 0, 1.3, 0, 0, "gold", "n" },
	{ "s", 6.1, 17.2, 0, 0.9, 0, 0, "jelly" },
	{ "s", -6.1, 17.2, 0, 0.9, 0, 0, "jelly" },
	{ "s", 0, 17.2, 6.1, 0.9, 0, 0, "jelly" },
	{ "s", 0, 17.2, -6.1, 0.9, 0, 0, "jelly" },
}
local LENS = Vector3.new(0, 23.0, -6.4) -- bout de la lunette : départ du faisceau (repère de l'Observatoire)

-- Kiosque (repère : pied du comptoir, −Z vers le centre de la place) : comptoir, plateau, fond, 4
-- poteaux, auvent à 5 bandes menthe et blanches, enseigne (étiquette world.kiosk), outils de Big Plop
local KIOSK: { RanchKit.Row } = {
	{ "b", 0, 1.3, -0.6, 6, 2.6, 2.2, "white" },
	{ "b", 0, 2.75, -0.7, 6.6, 0.3, 2.6, "mint" },
	{ "b", 0, 2.2, 1.4, 6, 4.4, 0.3, "cream" },
	{ "c", -3.0, 2.8, 1.4, 0.45, 5.6, 0, "white" },
	{ "c", 3.0, 2.8, 1.4, 0.45, 5.6, 0, "white" },
	{ "c", -3.0, 2.4, -2.0, 0.45, 4.8, 0, "mint" },
	{ "c", 3.0, 2.4, -2.0, 0.45, 4.8, 0, "mint" },
	{ "b", -2.6, 5.35, -0.4, 1.32, 0.22, 4.6, "mint", nil, -14, 0, 0 },
	{ "b", -1.3, 5.35, -0.4, 1.32, 0.22, 4.6, "white", nil, -14, 0, 0 },
	{ "b", 0, 5.35, -0.4, 1.32, 0.22, 4.6, "mint", nil, -14, 0, 0 },
	{ "b", 1.3, 5.35, -0.4, 1.32, 0.22, 4.6, "white", nil, -14, 0, 0 },
	{ "b", 2.6, 5.35, -0.4, 1.32, 0.22, 4.6, "mint", nil, -14, 0, 0 },
	{ "b", 0, 6.6, -2.3, 4.6, 1.3, 0.3, "pink" },
	{ "c", -1.6, 3.07, -0.8, 1.3, 0.35, 0, "gold", "f" },
	{ "b", 1.5, 3.15, -0.8, 1.6, 0.5, 0.6, "jelly" },
}
local KIOSK_SIGN = 13

-- Prairie v2 (repère : centre du jardin, −Z vers la place) : disque fleuri Ø 24, allée, 24 fleurs,
-- panneau (étiquette world.meadow), 4 buissons ; le tout dans le disque de rayon 12 (WorldLayout.spec)
local MEADOW: { RanchKit.Row } = {
	{ "c", 0, 0.1, 0, 24, 0.2, 0, "grass" },
	{ "c", 0, 0.12, 0, 9, 0.22, 0, "path" },
}
local FLOWER_COLORS = { "pink", "lemon", "lilac", "sky" }
for i = 1, 12 do
	local a = math.rad(30 * (i - 1))
	local d = if i % 2 == 0 then 1.1 else 0.9
	table.insert(
		MEADOW,
		{ "s", 6.5 * math.cos(a), 0.2 + d / 2, 6.5 * math.sin(a), d, 0, 0, FLOWER_COLORS[(i - 1) % 4 + 1] }
	)
end
for i = 1, 12 do
	local a = math.rad(15 + 30 * (i - 1))
	local d = if i % 2 == 0 then 0.9 else 1.1
	table.insert(
		MEADOW,
		{ "s", 9.6 * math.cos(a), 0.2 + d / 2, 9.6 * math.sin(a), d, 0, 0, FLOWER_COLORS[i % 4 + 1] }
	)
end
table.insert(MEADOW, { "b", 0, 2.1, -10.6, 0.4, 3.8, 0.4, "wood" })
table.insert(MEADOW, { "b", 0, 4.0, -10.6, 4, 2, 0.3, "sign" })
local MEADOW_SIGN = #MEADOW
for i = 1, 4 do
	local a = math.rad(45 + 90 * (i - 1))
	table.insert(MEADOW, { "s", 10.4 * math.cos(a), 1.2, 10.4 * math.sin(a), 2.4, 0, 0, "bush" })
end

-- Glaçons sous la lisse haute (Y 3,2) de la clôture de devant (Z 0,5), entre les poteaux (± 11,25, ± 18,
-- ± 24,75) et hors du portail (|X| ≤ 4,5) : 6 de chaque côté, blancs (Ice) et rouges, en losange
local ICICLE_X = { 6.5, 9.3, 13.2, 16.0, 20.0, 22.8 }

type Built = { folder: Folder, parts: { BasePart }, sign: BasePart? }

local state = {
	root = nil :: Folder?,
	observatory = nil :: Built?,
	beam = nil :: BasePart?,
	beamTarget = 0,
	kiosk = nil :: Built?,
	meadow = nil :: Built?,
	hidden = {} :: { [BasePart]: number }, -- pièces de la Prairie du serveur cachées : transparence d'origine
	icicles = {} :: { [number]: Built },
	current = 0, -- ranch courant (RanchLook.currentRanch) pour le costume d'hiver
	atelierVersion = -1,
	atelierVisible = false,
	declared = false,
}

-- =============================================================================================
-- Outils
-- =============================================================================================

local function ranchModel(slot: number): Instance?
	if slot < 1 or slot > RANCHES then
		return nil
	end
	local root = workspace:FindFirstChild("Wobbleton")
	local list = root and root:FindFirstChild("Ranches")
	return list and list:FindFirstChild(tostring(slot))
end

local function mySlot(): number
	return Util.safe("WorldStateController.mySlot", 0, WorldStateController.mySlot)
end

local function field(t: any, key: string): any
	return if type(t) == "table" then t[key] else nil
end

local function rootFolder(): Folder
	local f = state.root
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
	made.Name = "WorldV2"
	made.Parent = world
	state.root = made
	return made
end

local function pruneRoot()
	local f = state.root
	if f and #f:GetChildren() == 0 then
		f:Destroy()
		state.root = nil
	end
end

local function declare()
	if state.declared then
		return
	end
	state.declared = true
	VisualBudget.declare("world", (VisualBudget.LIMITS :: any).world)
	VisualBudget.declare("meadow", (VisualBudget.LIMITS :: any).meadow)
end

-- Construit les lignes `rows` au repère `base` dans un dossier `name` (budget `system` réservé avant)
local function build(name: string, base: CFrame, rows: { RanchKit.Row }, signIndex: number?): Built
	local folder = Instance.new("Folder")
	folder.Name = name
	local specs = RanchKit.rows({}, base, name, rows, PALETTE)
	local parts: { BasePart } = {}
	for i, spec in specs do
		parts[i] = RanchKit.create(spec, folder)
	end
	folder.Parent = rootFolder()
	return { folder = folder, parts = parts, sign = if signIndex then parts[signIndex] else nil }
end

local function destroy(b: Built?)
	if b then
		b.folder:Destroy()
	end
end

-- Repère au sol d'un point du monde, tourné vers le centre de la place (−Z vers la place)
local function facingPlaza(p: Vector3): CFrame
	local ground = Vector3.new(p.X, WorldLayout.groundY(p.X, p.Z), p.Z)
	local center = Vector3.new(0, ground.Y, 0)
	if (center - ground).Magnitude < 1e-3 then
		return CFrame.new(ground)
	end
	return CFrame.lookAt(ground, center)
end

-- =============================================================================================
-- Observatoire et faisceau (D10, D25)
-- =============================================================================================

-- Ranch visé par le faisceau : celui du héros d'une Jelly Ascend en cours, sinon le premier ranch dont
-- la Jelly Ascend est prête (le mien d'abord) ; 0 : aucun faisceau
local function beamTargetOf(payload: any): number
	local current = field(field(payload, "spectacle"), "current")
	local userId = field(current, "userId")
	local endsAt = field(current, "endsAt")
	if field(current, "kind") == "ascend" and type(userId) == "number" and userId > 0 then
		if type(endsAt) ~= "number" or Clock.now() < endsAt then
			for slot = 1, RANCHES do
				local ranch = Util.safe("WorldStateController.ranch", nil, WorldStateController.ranch, slot)
				if type(ranch) == "table" and ranch.userId == userId then
					return slot
				end
			end
		end
	end
	local my = mySlot()
	local mine = ranchModel(my)
	if mine and mine:GetAttribute("AscendReady") == true then
		return my
	end
	for slot = 1, RANCHES do
		if slot ~= my then
			local model = ranchModel(slot)
			if model and model:GetAttribute("AscendReady") == true then
				return slot
			end
		end
	end
	return 0
end

local function beamCFrame(slot: number): (CFrame, Vector3)
	local from = WorldLayout.observatory() * LENS
	local to = WorldLayout.toWorld(slot, Vector3.new(0, 2, 36))
	local d = to - from
	local length = math.min(d.Magnitude, BEAM_MAX)
	local mid = from + d.Unit * (length / 2)
	-- axe d'un Cylinder = X : tourné de 90° autour de Y pour suivre la direction du regard
	return CFrame.lookAt(mid, to) * CFrame.Angles(0, math.pi / 2, 0),
		Vector3.new(length, BEAM_WIDTH, BEAM_WIDTH)
end

local function syncBeam(target: number)
	if
		target == state.beamTarget
		and (target == 0 or (state.beam ~= nil and (state.beam :: BasePart).Parent ~= nil))
	then
		return
	end
	state.beamTarget = target
	local beam = state.beam
	if target == 0 then
		if beam then
			beam:Destroy()
			state.beam = nil
		end
		return
	end
	local cf, size = beamCFrame(target)
	if beam == nil or beam.Parent == nil then
		local obs = state.observatory
		if obs == nil then
			return
		end
		local spec: RanchKit.Spec = {
			key = "Beam",
			shape = "Cylinder",
			size = size,
			cf = cf,
			color = PALETTE.beam,
			material = Enum.Material.Neon,
		}
		state.beam = RanchKit.create(spec, obs.folder)
	else
		beam.Size = size
		beam.CFrame = cf
	end
end

local function syncObservatory(on: boolean, payload: any)
	if not on then
		if state.observatory then
			destroy(state.observatory)
			state.observatory = nil
			state.beam = nil
			state.beamTarget = 0
			VisualBudget.release("world", OBSERVATORY_PARTS + 1)
		end
		return
	end
	if state.observatory == nil or state.observatory.folder.Parent == nil then
		declare()
		if not VisualBudget.take("world", OBSERVATORY_PARTS + 1) then
			return
		end
		state.observatory = build("Observatory", WorldLayout.observatory(), OBSERVATORY)
		state.beam = nil
		state.beamTarget = 0
	end
	syncBeam(beamTargetOf(payload))
end

-- =============================================================================================
-- Kiosque de Big Plop (D21, INT-B4-KIOSK)
-- =============================================================================================

local modules: { [string]: any } = {}
local function lazy(name: string, get: () -> any): any
	local m = modules[name]
	if m == nil then
		local ok, mod = pcall(get)
		m = if ok and type(mod) == "table" then mod else false
		modules[name] = m
	end
	return if m == false then nil else m
end

local function panelController(): any
	return lazy("PanelController", function()
		return require(Client.UI.PanelController) :: any
	end)
end

local function upgradeSnapshot(): any
	return lazy("UpgradeSnapshot", function()
		return require(Client.UI.UpgradeSnapshot) :: any
	end)
end

local function upgradeView(): any
	return lazy("UpgradeView", function()
		return require(Client.UI.Hud.UpgradeView) :: any
	end)
end

-- Une ligne de l'Atelier n'est pas cachée dans cet instantané (une ligne coupée par un interrupteur du
-- serveur est cachée, D8 du lot B2)
local function atelierVisible(snap: any): boolean
	local view = upgradeView()
	if view == nil then
		return false
	end
	local okLines, lines = pcall(view.lines, "workshop")
	if not okLines or type(lines) ~= "table" then
		return false
	end
	for _, id in lines do
		local ok, v = pcall(view.view, id, snap, 1)
		if ok and type(v) == "table" and v.hidden ~= true then
			return true
		end
	end
	return false
end

-- Le kiosque doit exister : l'écran Améliorations a son instantané (PanelController.available) et une ligne
-- de l'Atelier n'y est pas cachée ; revu à chaque évaluation (0,5 s au plus après un nouvel instantané)
local function kioskWanted(): boolean
	local pc = panelController()
	if pc == nil or type(pc.available) ~= "function" then
		return false
	end
	local ok, available = pcall(pc.available, "Upgrades")
	if not ok or available ~= true then
		return false
	end
	local mod = upgradeSnapshot()
	local okSnap, snap = pcall(function(): any
		return if mod then mod.current() else nil
	end)
	if not okSnap or type(snap) ~= "table" then
		return false
	end
	local version = if type(snap.version) == "number" then snap.version else -2
	if version ~= state.atelierVersion then
		state.atelierVersion = version
		state.atelierVisible = atelierVisible(snap)
	end
	return state.atelierVisible
end

local function syncKiosk(on: boolean)
	if not on then
		if state.kiosk then
			destroy(state.kiosk)
			state.kiosk = nil
			VisualBudget.release("world", KIOSK_PARTS)
		end
		return
	end
	if state.kiosk == nil or state.kiosk.folder.Parent == nil then
		declare()
		if not VisualBudget.take("world", KIOSK_PARTS) then
			return
		end
		state.kiosk = build("Kiosk", facingPlaza(WorldLayout.plaza("kiosk")), KIOSK, KIOSK_SIGN)
		local sign = (state.kiosk :: Built).sign
		if sign then
			sign:SetAttribute("LabelKey", "world.kiosk")
			sign:SetAttribute("LabelHeight", 1.6)
		end
	end
end

-- =============================================================================================
-- Prairie v2 (D9)
-- =============================================================================================

local function hideServerMeadow(world: Instance?)
	local meadow = world and world:FindFirstChild("Meadow")
	if meadow == nil then
		return
	end
	for _, d in meadow:GetDescendants() do
		if d:IsA("BasePart") and state.hidden[d] == nil then
			state.hidden[d] = d.Transparency
			if d.Transparency ~= 1 then
				d.Transparency = 1
			end
		end
	end
end

local function showServerMeadow()
	for part, original in state.hidden do
		-- une valeur réécrite par le serveur entre temps reste telle quelle
		if part.Parent ~= nil and part.Transparency == 1 and original ~= 1 then
			part.Transparency = original
		end
	end
	table.clear(state.hidden)
end

local function syncMeadow(on: boolean, world: Instance?)
	if not on then
		if state.meadow then
			destroy(state.meadow)
			state.meadow = nil
			VisualBudget.release("meadow", #MEADOW)
		end
		if next(state.hidden) ~= nil then
			showServerMeadow()
		end
		return
	end
	if state.meadow == nil or state.meadow.folder.Parent == nil then
		declare()
		if not VisualBudget.take("meadow", #MEADOW) then
			return
		end
		state.meadow = build("Meadow", facingPlaza(WorldLayout.meadowCenter(true)), MEADOW, MEADOW_SIGN)
		local sign = (state.meadow :: Built).sign
		if sign then
			sign:SetAttribute("LabelKey", "world.meadow")
			sign:SetAttribute("LabelHeight", 2)
		end
	end
	hideServerMeadow(world)
end

-- =============================================================================================
-- Glaçons du costume d'hiver (D30)
-- =============================================================================================

local function icicleRows(): { RanchKit.Row }
	local rows: { RanchKit.Row } = {}
	for _, side in { -1, 1 } do
		for k, x in ICICLE_X do
			local ice = k % 2 == 1
			table.insert(rows, {
				"b",
				side * x,
				2.45,
				0.5,
				0.32,
				1.1,
				0.32,
				if ice then "ice" else "cane",
				if ice then "i" else nil,
				0,
				45,
				0,
			})
		end
	end
	return rows
end
local ICICLES = icicleRows()

local function syncIcicles(on: boolean)
	local wanted: { [number]: boolean } = {}
	if on then
		local root = Util.localRoot()
		state.current = RanchLook.currentRanch(state.current, mySlot(), if root then root.Position else nil)
		local cur = state.current
		if cur >= 1 and cur <= RANCHES then
			wanted[cur] = true
			wanted[(cur - 2) % RANCHES + 1] = true
			wanted[cur % RANCHES + 1] = true
		end
	end
	for slot, b in state.icicles do
		if not wanted[slot] or b.folder.Parent == nil then
			destroy(b)
			state.icicles[slot] = nil
		end
	end
	for slot in wanted do
		if state.icicles[slot] == nil then
			state.icicles[slot] = build("Icicles" .. slot, WorldLayout.ranchCFrame(slot), ICICLES)
		end
	end
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Met le monde v2.0 dans l'état voulu (LightingController, toutes les 0,5 s et à chaque EventState) ;
-- idempotent : même état, rien de créé ni d'écrit
function WorldV2.update(ctx: Context)
	local my = mySlot()
	local mine = ranchModel(my)
	local tapis = mine ~= nil and mine:GetAttribute("TapisTier") ~= nil
	local monuments = mine ~= nil and mine:GetAttribute("Monuments") ~= nil
	local world = if type(ctx) == "table" then ctx.world else nil
	Util.guard(
		"WorldV2.observatory",
		syncObservatory,
		tapis,
		if type(ctx) == "table" then ctx.payload else nil
	)
	Util.guard("WorldV2.kiosk", syncKiosk, kioskWanted())
	Util.guard("WorldV2.meadow", syncMeadow, monuments, world)
	Util.guard(
		"WorldV2.icicles",
		syncIcicles,
		type(ctx) == "table" and ctx.ambience == true and ctx.winter == true
	)
	pruneRoot()
end

-- Pièces qui portent une étiquette fixe (mécanisme LabelKey de LightingController)
function WorldV2.labels(): { LabelAnchor }
	local out: { LabelAnchor } = {}
	for _, b in { state.kiosk, state.meadow } do
		local sign = if b then b.sign else nil
		if sign and sign.Parent ~= nil then
			local key = sign:GetAttribute("LabelKey")
			local height = sign:GetAttribute("LabelHeight")
			if type(key) == "string" then
				table.insert(
					out,
					{ part = sign, key = key, height = if type(height) == "number" then height else 2 }
				)
			end
		end
	end
	return out
end

-- La Prairie v2 est dessinée (celle du serveur et son étiquette sont cachées sur ce client)
function WorldV2.meadowV2(): boolean
	return state.meadow ~= nil
end

-- Le kiosque de Big Plop est construit (PromptController : invite □ « Atelier »)
function WorldV2.kioskOpen(): boolean
	return state.kiosk ~= nil and state.kiosk.folder.Parent ~= nil
end

-- Ranch visé par le faisceau de l'Observatoire (0 : aucun faisceau ou pas d'Observatoire)
function WorldV2.beamTarget(): number
	return if state.beam ~= nil then state.beamTarget else 0
end

-- Compteurs (specs, budgets)
function WorldV2.stats(): { [string]: number }
	local function count(b: Built?): number
		return if b then #b.parts else 0
	end
	local icicles = 0
	for _, b in state.icicles do
		icicles += #b.parts
	end
	return {
		observatory = count(state.observatory) + (if state.beam then 1 else 0),
		kiosk = count(state.kiosk),
		meadow = count(state.meadow),
		icicles = icicles,
		icicleRanches = (function(): number
			local n = 0
			for _ in state.icicles do
				n += 1
			end
			return n
		end)(),
		hidden = (function(): number
			local n = 0
			for _ in state.hidden do
				n += 1
			end
			return n
		end)(),
	}
end

-- Ranchs qui portent des glaçons (specs)
function WorldV2.icicleSlots(): { number }
	local out: { number } = {}
	for slot in state.icicles do
		table.insert(out, slot)
	end
	table.sort(out)
	return out
end

-- Tout retirer et rendre la Prairie du serveur (specs)
function WorldV2.stop()
	syncObservatory(false, nil)
	syncKiosk(false)
	syncMeadow(false, nil)
	syncIcicles(false)
	pruneRoot()
	state.current = 0
	state.atelierVersion = -1
	state.atelierVisible = false
end

return WorldV2
