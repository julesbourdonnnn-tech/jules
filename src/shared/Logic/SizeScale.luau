--!strict
-- SizeScale (paquet logic, docs/04 §12.1). Échelle de taille visuelle logarithmique et plafonds
-- d'affichage (GDD §4.2, §4.12, §6.6). La taille réelle et le nombre restent exacts ailleurs : ce
-- module ne fait que l'image.
--   échelle(S) = 1 + LogFactor × log10(max(1, S)) ; diamètre = BaseDiameter × échelle
-- (Balance.SizeScale). Plafonds : 4× dans un enclos ou le Bassin, échelle fixée par la selle pour
-- une monture (2,85×, 3,5×, 4×), 19× pour la silhouette du ranch et la statue de la place.
-- Toute entrée bizarre (NaN, ±inf, négatif, nil) donne une échelle finie ≥ 1.

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, math = type, math

local Balance = require(script.Parent.Parent.Config.Balance)

export type Where = "pen" | "pool" | "ride" | "silhouette" | "statue" | "free"

local SizeScale = {}

local CFG = Balance.SizeScale
local MAX_SIZE = Balance.Numbers.Max

-- Taille sûre dans [1 ; Max] (NaN et valeurs bizarres → 1)
local function sane(size: any): number
	if type(size) ~= "number" or size ~= size or size < 1 then
		return 1
	end
	if size > MAX_SIZE then
		return MAX_SIZE
	end
	return size
end

-- Plus grande échelle de selle (plafond d'une monture)
local function maxSaddleScale(): number
	local best = 1
	for _, saddle in Balance.Ride.Saddles do
		best = math.max(best, saddle.scale)
	end
	return best
end

local RIDE_CAP = maxSaddleScale()

-- Plafond d'affichage d'un lieu (math.huge : aucun)
local function capOf(where: any): number
	if where == "pen" or where == "pool" then
		return CFG.PenCap
	elseif where == "silhouette" or where == "statue" then
		return CFG.SilhouetteCap
	elseif where == "ride" then
		return RIDE_CAP
	end
	return math.huge
end

-- Échelle sans plafond (1× pour S ≤ 1 ; NaN → 1)
function SizeScale.scale(size: number): number
	return 1 + CFG.LogFactor * math.log10(sane(size))
end

-- Diamètre du corps en studs, sans plafond
function SizeScale.diameter(size: number): number
	return CFG.BaseDiameter * SizeScale.scale(size)
end

-- Échelle affichée selon le lieu (enclos 4×, monture fixée par la selle, silhouette et statue 19×)
function SizeScale.display(size: number, where: Where, saddle: number?): number
	local s = SizeScale.scale(size)
	if where == "ride" then
		local level = if type(saddle) == "number" and saddle == saddle then math.floor(saddle) else 0
		local def = Balance.Ride.Saddles[level]
		if def then
			return def.scale
		end
		-- aucune selle (ne devrait pas monter) : même plafond que l'enclos
		return math.min(s, CFG.PenCap)
	end
	return math.min(s, capOf(where))
end

-- La taille dépasse le plafond du lieu (couronne de taille)
function SizeScale.overCap(size: number, where: Where): boolean
	return SizeScale.scale(size) > capOf(where)
end

return SizeScale
