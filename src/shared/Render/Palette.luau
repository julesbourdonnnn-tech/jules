--!strict
-- Palette (paquet world) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Palette du monde et préréglages d'éclairage (GDD §11.3, §5.4) : couleurs pastel du plateau, de la
-- place, des rues et des collines ; préréglages jour, BOOP RUSH, Jelly Moon, fêtes, hiver « Frost &
-- Sprinkles » ; teinte discrète du Rush pour un nouveau (30 %). Données lues par WorldService et
-- LightingController ; couleurs des ranchs : Config/Cosmetics.RanchColors.

export type Preset = {
	clockTime: number,
	ambient: Color3,
	outdoorAmbient: Color3,
	brightness: number,
	tint: Color3,
	atmosphereColor: Color3,
	bloom: number,
	starCount: number,
	moonSize: number,
}

local Palette = {}

-- Préréglage d'éclairage ("day", "rush", "moon", "party", "winter")
function Palette.preset(name: string): Preset
	local _ = { name }
	error("TODO(world): Palette.preset")
end

-- Mélange de deux préréglages (teinte à 30 % pour un nouveau)
function Palette.blend(a: Preset, b: Preset, alpha: number): Preset
	local _ = { a, b, alpha }
	error("TODO(world): Palette.blend")
end

return Palette
