--!strict
-- ProfileRepair (paquet ranch) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Données lues = données à revalider (GDD §12.6) : après migrate + reconcile, revérifie chaque champ
-- du profil (types, bornes, NaN, tableaux denses allongés à Species.List, uids existants, lieux,
-- emplacements de Meilleur Ami uniques, tenues portées par des uids existants, capacités) et répare
-- avec une valeur sûre. Pur (aucun service Roblox). Appelé par DataService (note INT-REPAIR) ; les
-- réparations sont comptées par DiagnosticsService (Signals.ProfileRepaired).

local ProfileRepair = {}

-- Répare en place ; rend la liste des champs réparés (vide = sain)
function ProfileRepair.repair(data: { [string]: any }): { string }
	local _ = { data }
	error("TODO(ranch): ProfileRepair.repair")
end

return ProfileRepair
