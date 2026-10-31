--!strict
-- CongaRenderer — paquet « client-world » (STUB du contrat : docs/04-architecture.md §13.7).
-- Rendu de toutes les créatures (files, sauvages, perchés, Gloomwisps, Comète) dans
-- workspace.ClientWorld (dossier client), avec NebbyBuilder, niveaux de détail et réserves.
-- Responsabilités :
--   * files des AUTRES joueurs : nœuds échantillonnés sur le miroir de miettes serveur
--     (WorldStateController.trail(slot):sample(n, Spacing, HeadGap)), premier tronçon raccordé au
--     personnage affiché s'il est chargé ; file du joueur LOCAL : Trail local alimenté chaque image
--   * un SEUL workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged) par image ;
--     files lointaines (> 120 studs) à 20 Hz ; LOD < 50 complet, 50-120 boule, > 120 : sauvages
--     masqués, files réduites à la tête + étiquette « ×N » ; budgets §12.8 (≤ 100 complets,
--     ≤ 1 500 pièces, Highlights, lumières) ; Graphismes légers : distances × 0,6
--   * animations : vague dans la file, face au précédent, inclinaison dans les virages, danse à
--     l'arrêt (> 1 s), rebond et clignement des sauvages, regard vers le joueur proche (≤ 15),
--     flânerie SeededPath ; saut de capture (parabole 0,3 s, écrasement), arcs de dispersion
--     (0,55 s) + étourdissement, marche de parade vers le Nid puis saut sur les perchoirs (≤ 2 s)
--   * lisibilité (§6.4) : anneaux rose (coupables) / doré (Guard Links) quand un autre joueur est à
--     ≤ 20 studs ; contour pointillé rose de sa propre queue si un non-équipier est à ≤ 15 studs ;
--     bulles bleues (escorte), bulle dorée (bouclier), étincelles roses (immunité), « ? » doré sur
--     un Nebby inconnu de l'Atlas ; styles et auras de file (Cosmetics)
--   * Nids (attributs de Nest_XX) : perchés (PerchData), « +N » des 8 meilleurs du Nid local,
--     perchoir qui pousse, panneau BillboardGui (nom, ★ R, titre traduit), constellation (Y = 45),
--     liens d'équipage la nuit ; tableau de la stèle (attributs Live / Record / Weekly)
--   * Gloomwisps (tremblement, Beam d'aperçu de 15 studs) et Comète (ciel, orbe, porteur)
-- GDD : §4.6 (position des Nebbies), §5.2, §6.4, §9.3, §9.4, §11.6, §12.4, §12.8.
-- Dépendances : StateController, Util/Prefs, WorldStateController, Render/NebbyBuilder,
-- Logic/Trail, Logic/WorldLayout, Config/*, Shared/Util/Clock.

local CongaRenderer = {}

function CongaRenderer.Init() end

function CongaRenderer.Start() end

-- Positions rendues des nœuds de la file d'un slot (dernière image)
function CongaRenderer.nodePositions(_slot: number): { Vector3 }
	error("TODO(client-world): CongaRenderer.nodePositions")
end

-- Modèle rendu du nœud `index` du slot (nil si masqué)
function CongaRenderer.nodeModel(_slot: number, _index: number): Model?
	error("TODO(client-world): CongaRenderer.nodeModel")
end

-- Modèle rendu d'un sauvage (nil si masqué)
function CongaRenderer.wildModel(_id: number): Model?
	error("TODO(client-world): CongaRenderer.wildModel")
end

-- Nombre de pièces de Nebbies actuellement rendues (budget)
function CongaRenderer.renderedParts(): number
	error("TODO(client-world): CongaRenderer.renderedParts")
end

return CongaRenderer
