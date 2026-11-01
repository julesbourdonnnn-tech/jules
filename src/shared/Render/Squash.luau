--!strict
-- Squash (paquet world) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Profils d'écrasement et d'étirement (GDD §9.1, §9.3, §9.4), purs : press, perfect, land, hatch,
-- fuse, sneeze, hop, mount, et l'animation de repos (rebond de 1,2 s calé sur le PERFECT, écrasement
-- au contact, tremblement amorti à la fréquence de l'espèce). Amplitudes × 0,5 en Mouvement réduit.

-- Profils (GDD §9.4) : étapes { échelle (X, Y, Z), durée, style d'easing }
local PROFILES = {
	press = {
		{ 1.35, 0.60, 1.35, 0.06, "QuadOut" },
		{ 0.85, 1.25, 0.85, 0.12, "QuadOut" },
		{ 1, 1, 1, 0.35, "ElasticOut" },
	},
	perfect = {
		{ 1.45, 0.50, 1.45, 0.06, "QuadOut" },
		{ 0.85, 1.25, 0.85, 0.12, "QuadOut" },
		{ 1, 1, 1, 0.35, "ElasticOut" },
	},
	land = { { 1.3, 0.7, 1.3, 0.08, "QuadOut" }, { 1, 1, 1, 0.2, "BackOut" } },
	hatch = {
		{ 1.4, 0.6, 1.4, 0.1, "QuadOut" },
		{ 1.1, 1.1, 1.1, 0.25, "BackOut" },
		{ 1, 1, 1, 0.1, "QuadOut" },
	},
	fuse = {
		{ 0.6, 0.6, 0.6, 0.01, "Linear" },
		{ 1.25, 1.25, 1.25, 0.2, "ElasticOut" },
		{ 1, 1, 1, 0.2, "ElasticOut" },
	},
	sneeze = { { 1.5, 0.6, 1.5, 0.08, "QuadOut" }, { 1, 1, 1, 0.3, "BackOut" } },
	hop = {
		{ 0.85, 1.25, 0.85, 0.08, "QuadOut" },
		{ 1.3, 0.7, 1.3, 0.08, "QuadOut" },
		{ 1, 1, 1, 0.1, "QuadOut" },
	},
	mount = { { 1.25, 0.75, 1.25, 0.12, "QuadOut" }, { 1, 1, 1, 0.2, "BackOut" } },
}

local Squash = {}

Squash.PROFILES = PROFILES

-- (sx, sy, sz, fini) du profil à t secondes
function Squash.sample(profile: string, t: number, amplitude: number?): (number, number, number, boolean)
	local _ = { profile, t, amplitude }
	error("TODO(world): Squash.sample")
end

-- (sx, sy, sz, hauteur en × diamètre) de l'animation de repos
function Squash.idle(
	t: number,
	offset: number,
	wobbleHz: number,
	wobbleAmp: number
): (number, number, number, number)
	local _ = { t, offset, wobbleHz, wobbleAmp }
	error("TODO(world): Squash.idle")
end

-- Durée d'un profil (s)
function Squash.duration(profile: string): number
	local _ = { profile }
	error("TODO(world): Squash.duration")
end

return Squash
