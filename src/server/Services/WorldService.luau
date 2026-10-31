--!strict
-- WorldService — paquet « world » (STUB du contrat : docs/04-architecture.md §11.3).
-- Construit Lumora en primitives au démarrage (Init, synchrone, aucun yield) avec World/Build et
-- Logic/WorldLayout, puis expose les points d'accroche aux autres services.
-- Responsabilités :
--   * workspace.Lumora (Folder) : Island (disque Grass, Clairière, sol et rebord du Cratère,
--     18 fissures Néon, falaise de 48 WedgeParts, 36 murs invisibles r = 181), Beacon (étages
--     Marble, anneaux Néon tagués "BeaconRing", étoile, Beam "SkyBeam", anneau de dépôt
--     "BeaconDeposit", stèle "Board"), Nests (Nest_01 … Nest_12 : Platform, Gate { PostL, PostR,
--     Arch (7 pièces Néon tag "NestArch") }, Observatory, BillboardAnchor, Spawn (SpawnLocation
--     Neutral, Duration 0, transparente, sans collision), Perches (Folder)), Paths (pas japonais),
--     Lanterns (36, PointLight à r 90 et 60 seulement), Decor (Meadow, Glade, Crater), Islets
--     (tag Float), Clouds (Build.cloud, tag Float)
--   * attributs initiaux des Nids (Slot, OwnerUserId = 0, …, voir docs §3.2) ; Nid libre gris sans lumière
--   * ModelStreamingMode = Persistent pour Island, Beacon et chaque Nid
--   * Terrain.Clouds (Cover 0,6, Color (220, 200, 255)) et World/Lighting.applyTwilight() + valeurs
--     de base de Events.Lighting.Base
--   * budget ≤ Zones.PartBudget pièces (≈ 2 000-2 500), décor ancré et sans collision
--   * perchoirs créés / détruits à la demande (setPerchCount) : Cylinder Wood Ø 2,2 × 1,2 + anneau
--     Néon fin (couleur du Nid), CanCollide = false, aux positions WorldLayout.perchCFrame
-- GDD : §11.1-§11.4, §11.7, §11.5 (base), §12.2.
-- Dépendances : World/Build, World/Lighting, Logic/WorldLayout, Config/Zones, Config/Cosmetics,
-- Config/Events.

local WorldService = {}

function WorldService.Init() end

function WorldService.Start() end

function WorldService.root(): Folder
	error("TODO(world): WorldService.root")
end

function WorldService.nest(_slot: number): Model
	error("TODO(world): WorldService.nest")
end

function WorldService.spawnLocation(_slot: number): SpawnLocation
	error("TODO(world): WorldService.spawnLocation")
end

-- Couleurs de la plateforme et de l'arche (nil = Nid libre : gris, sans lumière)
function WorldService.setNestAppearance(_slot: number, _platform: Color3?, _arch: Color3?)
	error("TODO(world): WorldService.setNestAppearance")
end

-- Crée ou détruit les pièces de perchoir pour qu'il en existe exactement `count` (0-46)
function WorldService.setPerchCount(_slot: number, _count: number)
	error("TODO(world): WorldService.setPerchCount")
end

function WorldService.beacon(): Model
	error("TODO(world): WorldService.beacon")
end

-- Stèle du tableau des congas (attributs Live / Record / Weekly posés par LeaderboardService)
function WorldService.board(): BasePart
	error("TODO(world): WorldService.board")
end

-- Nombre de BasePart construites (budget §11.7)
function WorldService.partCount(): number
	error("TODO(world): WorldService.partCount")
end

return WorldService
