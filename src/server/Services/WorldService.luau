--!strict
-- WorldService (paquet world) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Construit Wobbleton à partir de Logic/WorldLayout (GDD §11) : plateau, collines, murs invisibles
-- du bord, place (MEGA pad, statue, boutique, Autel de la Lune, jarre de la jauge, scène de Big Plop,
-- fontaine dorée, 5 tableaux), rues, quartiers, lampadaires (1 lumière sur 4), Prairie des copains,
-- 16 ranchs (clôtures + mur invisible de 12 studs, portail de gelée non solide côté serveur, dalles,
-- 18 décorations cachées tant qu'elles ne sont pas construites, Pot, Cuve, Bassin, bol, coussin,
-- étagère, panneau). Tout est ancré et CanTouch = false ; seuls les solides de la liste du GDD §11.1
-- collisionnent ; ≤ 4 500 pièces. Construction protégée (pcall par bloc) : un bloc en panne est
-- compté par Diagnostics, le reste se construit. Clés de profil : aucune. Remotes : aucun.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)

local WorldService = {}

-- Construit le monde une seule fois (idempotent) et rend workspace.Wobbleton
function WorldService.build(): Folder
	error("TODO(world): WorldService.build")
end

-- Modèle du ranch (Ranches/<slot>)
function WorldService.ranchModel(slot: number): Model?
	local _ = { slot }
	error("TODO(world): WorldService.ranchModel")
end

-- Couleur du propriétaire (clôtures, panneau) ; gris sans lumière si libre (userId 0)
function WorldService.setRanchOwner(slot: number, userId: number, color: Color3?)
	local _ = { slot, userId, color }
	error("TODO(world): WorldService.setRanchOwner")
end

-- Montre les décorations construites, l'aspect du Tapis, la Cuve et le Bassin
function WorldService.setRanchBuild(slot: number, tiles: Types.Tiles, vat: boolean, pool: boolean)
	local _ = { slot, tiles, vat, pool }
	error("TODO(world): WorldService.setRanchBuild")
end

-- Attributs de la statue (dessinée par le client)
function WorldService.setStatue(species: number, mutation: number, size: number, name: string)
	local _ = { species, mutation, size, name }
	error("TODO(world): WorldService.setStatue")
end

-- Remplissage de la jarre de la jauge (0 … 1)
function WorldService.setGauge(ratio: number)
	local _ = { ratio }
	error("TODO(world): WorldService.setGauge")
end

-- Pièces construites (budget ≤ 4 500)
function WorldService.partCount(): number
	error("TODO(world): WorldService.partCount")
end

return WorldService
