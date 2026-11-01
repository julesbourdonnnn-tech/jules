--!strict
-- SizeScale (paquet logic) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Échelle de taille visuelle logarithmique et plafonds d'affichage (GDD §4.2, §4.12, §6.6).
-- échelle(S) = 1 + LogFactor × log10(max(1, S)) ; diamètre = BaseDiameter × échelle (Balance.SizeScale).

export type Where = "pen" | "pool" | "ride" | "silhouette" | "statue" | "free"

local SizeScale = {}

-- Échelle sans plafond (1× pour S ≤ 1 ; NaN → 1)
function SizeScale.scale(size: number): number
	local _ = { size }
	error("TODO(logic): SizeScale.scale")
end

-- Diamètre du corps en studs, sans plafond
function SizeScale.diameter(size: number): number
	local _ = { size }
	error("TODO(logic): SizeScale.diameter")
end

-- Échelle affichée selon le lieu (enclos 4×, monture fixée par la selle, silhouette et statue 19×)
function SizeScale.display(size: number, where: Where, saddle: number?): number
	local _ = { size, where, saddle }
	error("TODO(logic): SizeScale.display")
end

-- La taille dépasse le plafond du lieu (couronne de taille)
function SizeScale.overCap(size: number, where: Where): boolean
	local _ = { size, where }
	error("TODO(logic): SizeScale.overCap")
end

return SizeScale
