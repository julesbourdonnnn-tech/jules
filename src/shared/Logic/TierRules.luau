--!strict
-- TierRules (paquet A1, docs/04 §27.7). Paliers nommés des familles d'amélioration (GDD §4.6,
-- Annexe B.4) : « Nappe pique-nique » … « Galaxie » du Tapis, 9 paliers des Gants, 5 tabliers de
-- l'École, 3 aspects de l'Enclos. Source unique : Config/Upgrades.Families[].tiers (seuil `from`
-- en niveaux DE LA FAMILLE, clé de texte) ; Config/Visuals.Tiers (seuils du rendu) doit dire la même
-- chose (TierRules.spec le vérifie).
-- Le Tapis Étoilé continue la numérotation du Tapis à Goûter (même ligne, même palier de ranch) :
-- TierRules.of("star", 1) = 5 (« Étoilé », Tapis 13), TierRules.of("star", 5) = 6 (« Galaxie »).
-- Palier 0 = aucun palier encore (Gants et École au niveau 0, famille sans palier, id inconnu).
-- Pur, déterministe, jamais d'erreur (niveau illisible → 0, niveau au-delà du maximum → maximum).

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, math = type, math

local Upgrades = require(script.Parent.Parent.Config.Upgrades)

local TierRules = {}

-- Premier numéro de palier de chaque famille (le Tapis Étoilé suit les 4 paliers du Tapis)
local OFFSET: { [string]: number } = {}
for _, def in Upgrades.Families do
	OFFSET[def.id] = 0
end
do
	local snack = Upgrades.ById.snack
	if snack and Upgrades.ById.star then
		OFFSET.star = #snack.tiers
	end
end

-- Niveau entier de [0 ; levels] (illisible → 0)
local function levelOf(def: Upgrades.FamilyDef, level: any): number
	if type(level) ~= "number" or level ~= level then
		return 0
	end
	return math.clamp(math.floor(level), 0, def.levels)
end

-- Index (1 …) du dernier palier atteint dans la famille, 0 sinon
local function localTier(def: Upgrades.FamilyDef, level: number): number
	local found = 0
	for i, tier in def.tiers do
		if level >= tier.from then
			found = i
		end
	end
	return found
end

-- Palier d'une famille à un niveau (niveau de la famille ; Tapis Étoilé : 0 … 8)
function TierRules.of(familyId: string, level: number): number
	local def = Upgrades.ById[familyId]
	if def == nil then
		return 0
	end
	local i = localTier(def, levelOf(def, level))
	if i == 0 then
		return 0
	end
	return (OFFSET[familyId] or 0) + i
end

-- Clé de texte du palier atteint (nil : aucun palier)
function TierRules.key(familyId: string, level: number): string?
	local def = Upgrades.ById[familyId]
	if def == nil then
		return nil
	end
	local i = localTier(def, levelOf(def, level))
	if i == 0 then
		return nil
	end
	return def.tiers[i].key
end

-- Nouveau palier atteint en passant de `from` à `to` (achat ×1, ×10 ou Max) : son numéro, sinon nil
-- (Celebrate "tier", RanchService : un seul palier annoncé, le plus haut)
function TierRules.crossed(familyId: string, from: number, to: number): number?
	local a, b = TierRules.of(familyId, from), TierRules.of(familyId, to)
	if b > a then
		return b
	end
	return nil
end

-- Palier du Tapis de la ligne « snack » (Tapis à Goûter puis Tapis Étoilé) : attribut TapisTier
function TierRules.tapis(snack: number, star: number): number
	local s = TierRules.of("star", star)
	if s > 0 then
		return s
	end
	return TierRules.of("snack", snack)
end

-- Nombre de paliers d'une famille (Tapis : 4 + 2 du Tapis Étoilé, numérotés à la suite)
function TierRules.count(familyId: string): number
	local def = Upgrades.ById[familyId]
	if def == nil then
		return 0
	end
	return (OFFSET[familyId] or 0) + #def.tiers
end

return TierRules
