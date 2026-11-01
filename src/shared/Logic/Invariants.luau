--!strict
-- Invariants (paquet logic) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Invariants d'un profil et du serveur, purs (zéro bug, couche c du GDD §12.10) : vérifiés à chaque
-- tick du robot de longue durée (tests/harness/Soak), après chaque mutation en Studio, et avant
-- chaque sauvegarde. Rendent la liste des violations (vide = sain) ; ne réparent jamais.

local Invariants = {}

-- Pièces, Pot, Fame, tailles finies et bornées ; places ≤ capacités (24 / 60 / 20) ; un squishy par emplacement de Meilleur Ami ; tenues portées par des uid existants ; tableaux denses ; niveaux bornés
function Invariants.profile(data: { [string]: any }): { string }
	local _ = { data }
	error("TODO(logic): Invariants.profile")
end

-- Nombre fini dans [min ; max]
function Invariants.number(x: any, min: number, max: number): boolean
	local _ = { x, min, max }
	error("TODO(logic): Invariants.number")
end

-- Tableau séquentiel sans trou
function Invariants.dense(t: any): boolean
	local _ = { t }
	error("TODO(logic): Invariants.dense")
end

-- uid valide (base 36, 1 à 8 caractères)
function Invariants.uid(x: any): boolean
	local _ = { x }
	error("TODO(logic): Invariants.uid")
end

return Invariants
