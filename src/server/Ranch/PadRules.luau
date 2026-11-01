--!strict
-- Règles des dalles du ranch (paquet ranch, GDD §4.6, Config/Pads) : une dalle est-elle allumée
-- (achetable) pour ce profil ? Pur (lit le profil, ne le modifie jamais). Lu par RanchService
-- (l'attente de 0,6 s ne commence que sur une dalle allumée) et par EconomyService.buyTile (le panneau
-- et □ n'achètent qu'une dalle allumée). Le client dessine les dalles avec la même règle (note
-- d'intégration client-world / client-panels).
-- Règle :
--   * dalle inconnue, niveau maximal ou R < MinR : éteinte ;
--   * déjà découverte (bit tiles.seen) : allumée ;
--   * sinon : étape d'accueil ≥ revealStep (ou accueil fini) ET règle de découverte (always,
--     snackBought : Tapis acheté au moins une fois, pensFull : enclos + Bassin pleins, rMin : R ≥ MinR) ;
--   * pendant l'accueil, une dalle déjà achetée ne se rallume qu'à relightStep.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Pads = require(Shared.Config.Pads)
local Formulas = require(Shared.Logic.Formulas)

local PadRules = {}

local function num(x: any): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return 0
	end
	return x
end

-- Niveau actuel d'une dalle (le Lit douillet est un booléen : 0 ou 1)
function PadRules.level(data: { [string]: any }, tile: string): number
	local tiles = if type(data) == "table" then data.tiles else nil
	if type(tiles) ~= "table" then
		return 0
	end
	local v = tiles[tile]
	if type(v) == "boolean" then
		return if v then 1 else 0
	end
	return math.max(0, math.floor(num(v)))
end

-- Places d'enclos (Bassin compris) occupées, et capacité
function PadRules.penUse(data: { [string]: any }): (number, number)
	local used = 0
	if type(data.squishies) == "table" then
		for _, rec in data.squishies do
			if type(rec) == "table" and (rec.at == "pen" or rec.at == "pool") then
				used += 1
			end
		end
	end
	local bigRanch = type(data.passes) == "table" and data.passes.BigRanch == true
	local capacity = Formulas.penCapacity(PadRules.level(data, "pens"), bigRanch)
	return used, capacity
end

-- La dalle est-elle allumée (achetable maintenant) ?
function PadRules.visible(data: { [string]: any }, tile: string): boolean
	if type(data) ~= "table" or type(tile) ~= "string" then
		return false
	end
	local def = (Pads.Defs :: any)[tile]
	local price = (Balance.Tiles :: any)[tile]
	if type(def) ~= "table" or type(price) ~= "table" then
		return false
	end
	local level = PadRules.level(data, tile)
	if level >= price.Levels then
		return false
	end
	local R = num(data.R)
	if R < (price.MinR or 0) then
		return false
	end
	local onboarding = if type(data.onboarding) == "table" then data.onboarding else {}
	local done = onboarding.done == true
	local step = num(onboarding.step)
	-- pendant l'accueil, une dalle déjà achetée une fois ne se rallume qu'à relightStep
	if not done and def.relightStep ~= nil and level >= 1 and step < def.relightStep then
		return false
	end
	local tiles = if type(data.tiles) == "table" then data.tiles else {}
	if bit32.band(math.floor(num(tiles.seen)) % 4294967296, def.seenBit) ~= 0 then
		return true
	end
	if not done and step < def.revealStep then
		return false
	end
	if def.rule == "always" then
		return true
	elseif def.rule == "snackBought" then
		return PadRules.level(data, "snack") >= 1
	elseif def.rule == "pensFull" then
		local used, capacity = PadRules.penUse(data)
		return used >= capacity
	elseif def.rule == "rMin" then
		return R >= (price.MinR or 0)
	end
	return false
end

return PadRules
