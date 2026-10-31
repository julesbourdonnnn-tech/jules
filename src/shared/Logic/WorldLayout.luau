--!strict
-- WorldLayout — paquet « logic » (STUB du contrat : docs/04-architecture.md §12.1).
-- Géométrie PURE de Lumora (aucune Instance) partagée par WorldService (construction),
-- SpawnService (grille), CongaService (portes, ports sûrs, Balise), NestService, EventService et
-- les clients (minicarte, rendu). Toutes les valeurs viennent de Config/Zones et Config/Balance.
-- Responsabilités :
--   * Nids : centre du Nid k = slot − 1 en (150 cos 30°k, 0, 150 sin 30°k), orienté vers le centre ;
--     porte à 19 studs côté centre (r = 131) ; boîte de parade 12 × 10 × 4 centrée sur la porte
--   * port sûr : point à < 25 studs (XZ) du centre de N'IMPORTE QUELLE porte
--   * anneau de la Balise 8 ≤ r ≤ 16 ; zone d'un point (anneaux XZ) ; hauteur du sol par zone
--   * grille d'apparition par zone (pas de 6 studs) excluant : r < 16, port sûr élargi (30 studs
--     autour de chaque porte), plateformes de Nid (20 studs), obstacles du décor (decor())
--   * perchoirs : 46 positions dans l'ordre Zones.Perches (arcs de 300° ouverts côté porte)
--   * décor seedé (Zones.Decor.Seed) : mêmes positions pour la construction et l'exclusion
--   * clampToIsland : ramène un point dans l'île (r ≤ Island.Radius − marge) au sol
-- GDD : §4.3, §4.7 (port sûr), §4.8 (porte), §11.1-§11.4.
-- Dépendances : Config/Zones, Config/Balance, Config/Events (sels), Logic/Hash.

local WorldLayout = {}

export type CrystalSpot = { cframe: CFrame, lit: boolean }
export type LanternSpot = { position: Vector3, lit: boolean }

export type DecorLayout = {
	puffblooms: { Vector3 },
	mushcaps: { Vector3 },
	fences: { CFrame },
	crystals: { CrystalSpot },
	floatingStones: { Vector3 },
	craterRocks: { Vector3 },
	cracks: { CFrame },
	islets: { Vector3 },
	clouds: { Vector3 },
	obstacles: { Vector3 }, -- tous les points à exclure de la grille (rayon Zones.Decor.ObstacleRadius)
}

function WorldLayout.radiusXZ(_pos: Vector3): number
	error("TODO(logic): WorldLayout.radiusXZ")
end

function WorldLayout.nestCenter(_slot: number): Vector3
	error("TODO(logic): WorldLayout.nestCenter")
end

-- Repère du Nid au sol, LookVector vers le centre de l'île
function WorldLayout.nestCFrame(_slot: number): CFrame
	error("TODO(logic): WorldLayout.nestCFrame")
end

-- Centre de la boîte de porte (Y = GateHeight / 2), LookVector vers le centre de l'île
function WorldLayout.gateCFrame(_slot: number): CFrame
	error("TODO(logic): WorldLayout.gateCFrame")
end

function WorldLayout.inGateBox(_slot: number, _pos: Vector3): boolean
	error("TODO(logic): WorldLayout.inGateBox")
end

-- Slot dont la porte est à moins de HarborRadius (XZ), sinon nil
function WorldLayout.harborSlot(_pos: Vector3): number?
	error("TODO(logic): WorldLayout.harborSlot")
end

function WorldLayout.inHarbor(_pos: Vector3): boolean
	error("TODO(logic): WorldLayout.inHarbor")
end

function WorldLayout.inOwnHarbor(_slot: number, _pos: Vector3): boolean
	error("TODO(logic): WorldLayout.inOwnHarbor")
end

function WorldLayout.inBeaconRing(_pos: Vector3): boolean
	error("TODO(logic): WorldLayout.inBeaconRing")
end

-- "meadow" | "glade" | "crater" | nil (Balise, Nids hors anneaux, hors île)
function WorldLayout.zoneAt(_pos: Vector3): string?
	error("TODO(logic): WorldLayout.zoneAt")
end

function WorldLayout.groundY(_x: number, _z: number): number
	error("TODO(logic): WorldLayout.groundY")
end

function WorldLayout.clampToIsland(_pos: Vector3, _margin: number?): Vector3
	error("TODO(logic): WorldLayout.clampToIsland")
end

-- Points de la grille d'apparition d'une zone (calculés une fois, mis en cache)
function WorldLayout.spawnPoints(_zoneKey: string): { Vector3 }
	error("TODO(logic): WorldLayout.spawnPoints")
end

-- Perchoir `index` (1-46) du Nid `slot`, dans l'ordre Zones.Perches
function WorldLayout.perchCFrame(_slot: number, _index: number): CFrame
	error("TODO(logic): WorldLayout.perchCFrame")
end

-- `count` points du port sûr à WelcomeDistance (12) devant la porte (Puffkins de bienvenue)
function WorldLayout.welcomePoints(_slot: number, _count: number): { Vector3 }
	error("TODO(logic): WorldLayout.welcomePoints")
end

function WorldLayout.observatoryCFrame(_slot: number): CFrame
	error("TODO(logic): WorldLayout.observatoryCFrame")
end

-- Étoile `index` (1 = première Supernova) de la constellation au-dessus de l'observatoire (Y = 45)
function WorldLayout.constellationPoint(_slot: number, _index: number): Vector3
	error("TODO(logic): WorldLayout.constellationPoint")
end

-- Stèle du tableau des congas (r = 12, face au sud)
function WorldLayout.boardCFrame(): CFrame
	error("TODO(logic): WorldLayout.boardCFrame")
end

function WorldLayout.pathStones(): { Vector3 }
	error("TODO(logic): WorldLayout.pathStones")
end

function WorldLayout.lanterns(): { LanternSpot }
	error("TODO(logic): WorldLayout.lanterns")
end

function WorldLayout.decor(): DecorLayout
	error("TODO(logic): WorldLayout.decor")
end

return WorldLayout
