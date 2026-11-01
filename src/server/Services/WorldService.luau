--!strict
-- WorldService (paquet world, docs/04 §3.1, §11.3). Construit Wobbleton à partir de Logic/WorldLayout
-- (GDD §11) : plateau, collines, murs invisibles du bord, place (MEGA pad, statue, boutique, Autel de
-- la Lune, jarre de la jauge, scène de Big Plop, fontaine dorée, 5 tableaux), rues, quartiers,
-- lampadaires (1 lumière sur 4), Prairie des copains, 16 ranchs (clôture + mur invisible de 30 studs,
-- portail de gelée non solide côté serveur, dalles, 18 décorations cachées tant qu'elles ne sont pas
-- construites, Pot, Cuve, Bassin, bol, coussin, étagère, panneau) et le point d'apparition neutre.
-- Règle robuste (docs/04 §1 n° 12, §17.3) : tout est ancré et CanTouch = false ; seules les boîtes
-- de WorldLayout.solids() collisionnent (pièces « Solid » invisibles, exactement ces boîtes : le
-- client, la capture au bond et les règles du serveur utilisent les mêmes) ; tout le décor visible
-- est non solide ; ≤ 4 500 pièces. Aucune règle de jeu ne lit ce monde : il n'est qu'une image.
-- Construction protégée (pcall par bloc) : un bloc en panne est compté par Diagnostics
-- (reportCaught("world:<bloc>")), le reste se construit. Clés de profil : aucune. Remotes : aucun.
-- Aides : src/server/World/{Parts,Town,Ranch,Decor}.luau ; décor partagé : Render/WorldDecor.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Species = require(Shared.Config.Species)
local Mutations = require(Shared.Config.Mutations)
local Balance = require(Shared.Config.Balance)
local WorldLayout = require(Shared.Logic.WorldLayout)
local Palette = require(Shared.Render.Palette)

local Server = ServerScriptService:WaitForChild("Server")
local DiagnosticsService = require(Server.Services.DiagnosticsService)
local World = Server.World
local Parts = require(World.Parts)
local Town = require(World.Town)
local Ranch = require(World.Ranch)

local WorldService = {}

-- Constantes publiques (specs, autres services)
WorldService.FOLDER_NAME = "Wobbleton"
WorldService.COLLISION_GROUP = "Characters" -- groupe des personnages, qui ne se touche pas lui-même
WorldService.PART_BUDGET = 4500 -- GDD §11.4, §12.9
WorldService.SOLID_TAG = Parts.SOLID_TAG
WorldService.RANCH_LIGHT_TAG = Ranch.LIGHT_TAG
WorldService.LAMP_LIGHT_TAG = Town.LAMP_TAG
WorldService.STATUE_NAME_MAX = 50 -- caractères (UTF-8) d'un nom de statue

local folder: Folder? = nil
local ranches: { [number]: Ranch.Handle } = {}
local failures: { string } = {} -- blocs en panne (spec, Diagnostics)

-- Diagnostics (rang 1) : un bloc en panne est compté ; jamais d'erreur levée vers l'appelant
local function report(where: string, err: any)
	table.insert(failures, where)
	local ok = pcall(DiagnosticsService.reportCaught, where, err)
	if not ok then
		warn(`[WorldService] {where} :`, err)
	end
end

local function protect(where: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		report(where, err)
	end
end

local function validSlot(slot: any): boolean
	return type(slot) == "number"
		and slot == slot
		and slot % 1 == 0
		and slot >= 1
		and slot <= WorldLayout.Const.Ranches
end

local function finite(x: any, default: number): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return default
	end
	return x
end

-- Range les boîtes de WorldLayout.solids() par bloc : plateau, murs de chaque ranch, maisons, bord.
-- Classement géométrique (et non par position dans la liste) : robuste si logic réordonne la liste.
type Sorted = {
	plate: WorldLayout.Box?,
	ranch: { [number]: { WorldLayout.Box } },
	houses: { WorldLayout.Box },
	edge: { WorldLayout.Box },
}

local function sortSolids(): Sorted
	local sorted: Sorted = { plate = nil, ranch = {}, houses = {}, edge = {} }
	for slot = 1, WorldLayout.Const.Ranches do
		sorted.ranch[slot] = {}
	end
	for i, box in WorldLayout.solids() do
		local p = box.cframe.Position
		local r = math.sqrt(p.X * p.X + p.Z * p.Z)
		if i == 1 or box.size.Y < WorldLayout.Const.SolidMinHeight then
			sorted.plate = box
		elseif r > WorldLayout.Const.WallRadius - 2 then
			table.insert(sorted.edge, box)
		else
			local slot = WorldLayout.ranchNear(p, 1)
			if slot ~= 0 then
				table.insert(sorted.ranch[slot], box)
			else
				table.insert(sorted.houses, box)
			end
		end
	end
	return sorted
end

-- Groupe de collision des personnages (docs/04 §3.3) : personne ne porte ni ne bloque personne
local function registerCollisionGroup()
	local name = WorldService.COLLISION_GROUP
	local ok, err = pcall(function()
		local registered = false
		local okCheck, value = pcall(function()
			return PhysicsService:IsCollisionGroupRegistered(name)
		end)
		registered = okCheck and value == true
		if not registered then
			PhysicsService:RegisterCollisionGroup(name)
		end
		PhysicsService:CollisionGroupSetCollidable(name, name, false)
	end)
	if not ok then
		report("world:collision", err)
	end
end

-- Construit le monde une seule fois (idempotent) et rend workspace.Wobbleton
function WorldService.build(): Folder
	local existing = folder
	if existing and existing.Parent ~= nil then
		return existing
	end
	table.clear(ranches)
	table.clear(failures)
	local root = Instance.new("Folder")
	root.Name = WorldService.FOLDER_NAME
	folder = root
	local sorted: Sorted = { plate = nil, ranch = {}, houses = {}, edge = {} }
	protect("world:layout", function()
		sorted = sortSolids()
	end)
	protect("world:plate", function()
		local plate = sorted.plate
		if plate then
			Town.plate(root, plate)
		end
	end)
	protect("world:hills", function()
		Town.hills(root)
	end)
	protect("world:walls", function()
		Town.walls(root, sorted.edge)
	end)
	protect("world:plaza", function()
		Town.plaza(root)
	end)
	protect("world:streets", function()
		Town.streets(root)
	end)
	protect("world:houses", function()
		Town.houses(root, sorted.houses)
	end)
	protect("world:lamps", function()
		Town.lamps(root)
	end)
	protect("world:meadow", function()
		Town.meadow(root)
	end)
	local ranchFolder = Parts.folder(root, "Ranches")
	for slot = 1, WorldLayout.Const.Ranches do
		protect("world:ranch" .. slot, function()
			ranches[slot] = Ranch.build(ranchFolder, slot, sorted.ranch[slot] or {})
		end)
	end
	protect("world:spawn", function()
		Town.spawn(root)
	end)
	-- une seule mise dans le workspace, monde complet (aucun client ne voit un monde à moitié bâti)
	root.Parent = workspace
	return root
end

-- Modèle du ranch (Ranches/<slot>)
function WorldService.ranchModel(slot: number): Model?
	if not validSlot(slot) then
		return nil
	end
	local handle = ranches[slot]
	if handle and handle.model.Parent ~= nil then
		return handle.model
	end
	return nil
end

-- Couleur du propriétaire (clôtures, panneau) ; gris sans lumière si libre (userId 0)
function WorldService.setRanchOwner(slot: number, userId: number, color: Color3?)
	if not validSlot(slot) then
		return
	end
	local handle = ranches[slot]
	if handle == nil then
		return
	end
	local id = finite(userId, 0)
	if id < 0 or id % 1 ~= 0 then
		id = 0
	end
	local occupied = id ~= 0
	local tint = if occupied and typeof(color) == "Color3"
		then color :: Color3
		else Palette.ranchColor(slot, occupied)
	protect("world:owner" .. slot, function()
		Ranch.setOwner(handle, id, tint)
		if not occupied then
			-- ranch libéré : rien du propriétaire précédent ne reste visible
			Ranch.setBuild(
				handle,
				{ snack = 0, decor = 0, pens = 0, cozyBed = false, seen = 0 },
				false,
				false
			)
		end
	end)
end

-- Montre les décorations construites, l'aspect du Tapis, la Cuve et le Bassin
function WorldService.setRanchBuild(slot: number, tiles: Types.Tiles, vat: boolean, pool: boolean)
	if not validSlot(slot) then
		return
	end
	local handle = ranches[slot]
	if handle == nil then
		return
	end
	protect("world:build" .. slot, function()
		Ranch.setBuild(handle, tiles, vat == true, pool == true)
	end)
end

-- Plaza/<nom> s'il existe (aucune erreur si un bloc a échoué)
local function plazaChild(name: string): Instance?
	local root = folder
	local plaza = if root then root:FindFirstChild("Plaza") else nil
	return if plaza then plaza:FindFirstChild(name) else nil
end

-- Nom tronqué à `max` caractères UTF-8 (UTF-8 invalide → "")
local function cleanName(name: any, max: number): string
	if type(name) ~= "string" then
		return ""
	end
	if utf8.len(name) == nil then
		return ""
	end
	if (utf8.len(name) :: number) <= max then
		return name
	end
	local cut = utf8.offset(name, max + 1)
	return if cut then string.sub(name, 1, cut - 1) else name
end

-- Attributs de la statue (dessinée par le client)
function WorldService.setStatue(species: number, mutation: number, size: number, name: string)
	local statue = plazaChild("Statue")
	if statue == nil then
		return
	end
	local s = finite(species, 0)
	if s % 1 ~= 0 or Species.ById[s] == nil then
		s = 0
	end
	local m = finite(mutation, 0)
	if m % 1 ~= 0 or m < 0 or m > Mutations.Count then
		m = 0
	end
	local z = math.clamp(finite(size, 0), 0, Balance.Numbers.Max)
	local n = cleanName(name, WorldService.STATUE_NAME_MAX)
	if s == 0 then
		m, z, n = 0, 0, ""
	end
	statue:SetAttribute("StatueSpecies", s)
	statue:SetAttribute("StatueMutation", m)
	statue:SetAttribute("StatueSize", z)
	statue:SetAttribute("StatueName", n)
end

-- Remplissage de la jarre de la jauge (0 … 1)
function WorldService.setGauge(ratio: number)
	local jar = plazaChild("GaugeJar")
	if jar == nil then
		return
	end
	local fill = math.clamp(finite(ratio, 0), 0, 1)
	if jar:GetAttribute("Fill") ~= fill then
		jar:SetAttribute("Fill", fill)
	end
	local jelly = jar:FindFirstChild("Jelly")
	if jelly and jelly:IsA("BasePart") then
		local height = Town.JAR_MIN_JELLY + (Town.JAR_MAX_JELLY - Town.JAR_MIN_JELLY) * fill
		local base = (jar :: Model).WorldPivot * CFrame.new(0, Town.JAR_JELLY_BOTTOM, 0)
		local size = Vector3.new(height, jelly.Size.Y, jelly.Size.Z)
		if jelly.Size ~= size then
			jelly.Size = size
			jelly.CFrame = base * CFrame.new(0, height / 2, 0) * Parts.UPRIGHT
		end
	end
end

-- Pièces construites (budget ≤ 4 500)
function WorldService.partCount(): number
	local root = folder
	if root == nil then
		return 0
	end
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

-- Blocs en panne pendant la dernière construction (fonction ajoutée : specs, Diagnostics)
function WorldService.failures(): { string }
	return table.clone(failures)
end

-- Pièces taguées « Solid » (fonction ajoutée : WorldBuild.spec)
function WorldService.solidParts(): { BasePart }
	local out: { BasePart } = {}
	local root = folder
	if root == nil then
		return out
	end
	for _, inst in CollectionService:GetTagged(Parts.SOLID_TAG) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(root) then
			table.insert(out, inst)
		end
	end
	return out
end

-- Création des états : groupe de collision des personnages, puis le monde (aucun yield)
function WorldService.Init()
	registerCollisionGroup()
	WorldService.build()
end

function WorldService.Start()
	-- rien : le monde est construit à Init, les autres services l'animent par l'API
end

return WorldService
