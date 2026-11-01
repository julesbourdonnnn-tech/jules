--!strict
-- Places des squishies d'un ranch (paquet ranch, GDD §4.7, §9.3, docs/04 §10.1 « Press »). Le serveur
-- ne connaît pas la flânerie d'un squishy (dessinée par le client à 2 studs au plus de sa place) : il
-- mesure la portée depuis le CENTRE DE SA PLACE. Règle sans état, identique côté client (note
-- d'intégration client-world) :
--   * enclos : place n° k = rang du squishy parmi les squishies « pen » du ranch, triés par uid dans
--     l'ordre de création (plus court d'abord, puis ordre alphabétique) → WorldLayout.penSlot(slot, k) ;
--   * Bassin : même règle parmi les squishies « pool » → WorldLayout.poolSlot(slot, k) ;
--   * clôture : place n° i = position de l'uid dans la liste de la clôture → WorldLayout.fencePoint.
-- Pur.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldLayout = require(Shared.Logic.WorldLayout)

local Places = {}

-- Ordre de création d'un uid base 36
function Places.before(a: string, b: string): boolean
	if #a ~= #b then
		return #a < #b
	end
	return a < b
end

-- Rang (1 …) de `uid` parmi les squishies de `records` au lieu `at` ; 0 s'il n'y est pas
function Places.rank(records: { [string]: any }, uid: string, at: string): number
	local rec = records[uid]
	if type(rec) ~= "table" or rec.at ~= at then
		return 0
	end
	local rank = 1
	for other, r in records do
		if other ~= uid and type(r) == "table" and r.at == at and Places.before(other, uid) then
			rank += 1
		end
	end
	return rank
end

-- Centre de la place d'un squishy d'enclos ou du Bassin (nil ailleurs)
function Places.center(slot: number, records: { [string]: any }, uid: string): Vector3?
	local rec = records[uid]
	if type(rec) ~= "table" then
		return nil
	end
	if rec.at == "pen" then
		return WorldLayout.penSlot(slot, Places.rank(records, uid, "pen"))
	elseif rec.at == "pool" then
		return WorldLayout.poolSlot(slot, Places.rank(records, uid, "pool"))
	end
	return nil
end

return Places
