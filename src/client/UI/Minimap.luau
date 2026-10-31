--!strict
-- Minimap — paquet « client-hud » (STUB du contrat : docs/04-architecture.md §13.13).
-- Minicarte circulaire en Frames, haut droite (−16, 16), 150 × 150 ; M / appui / croix bas →
-- 300 × 300. Calculée depuis les données serveur (miettes et événements), indépendante du streaming.
-- Contenu : un point par joueur (taille selon la longueur de file, couleur du Nid ; le local
-- distingué), Comète clignotante 2 Hz (porteur ou au sol), Balise, Gloomwisps en violet, Nids.
-- Mise à jour à 10 Hz (pas chaque image) ; réserve de Frames.
-- GDD : §6.4, §10.2, §9.4 (porteur).
-- Dépendances : Util/Prefs, UI/Root, UI/Theme, UI/Create, WorldStateController, InputController,
-- Logic/WorldLayout, Config/Cosmetics, Config/Zones, Shared/Util/Clock.

local Minimap = {}

function Minimap.Init() end

function Minimap.Start() end

function Minimap.setExpanded(_expanded: boolean)
	error("TODO(client-hud): Minimap.setExpanded")
end

function Minimap.toggle()
	error("TODO(client-hud): Minimap.toggle")
end

-- Position 2D (0-1, 0-1) d'un point du monde sur la carte (pur)
function Minimap.project(_worldPos: Vector3): Vector2
	error("TODO(client-hud): Minimap.project")
end

return Minimap
