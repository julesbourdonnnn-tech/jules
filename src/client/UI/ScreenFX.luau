--!strict
-- ScreenFX (paquet client-hud) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Effets d'écran (GDD §9.2, §9.4) : flash (≤ 30 %), lueur des bords (série PERFECT, combo), vignette
-- de couleur, flèches de bord d'écran (créature en fuite, squishy boopé, fuite la plus proche). Aucun
-- clignotement au-dessus de 3 Hz ; rien en Mouvement réduit sauf les flèches. Éléments décoratifs
-- marqués Decorative = true.

local ScreenFX = {}

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function ScreenFX.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function ScreenFX.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Flash (pas en Mouvement réduit)
function ScreenFX.flash(alpha: number, duration: number, color: Color3?)
	local _ = { alpha, duration, color }
	error("TODO(client-hud): ScreenFX.flash")
end

-- Lueur des bords
function ScreenFX.glow(color: Color3, duration: number, strength: number?)
	local _ = { color, duration, strength }
	error("TODO(client-hud): ScreenFX.glow")
end

-- Flèche de bord d'écran vers une position (nil : retirée)
function ScreenFX.arrow(id: string, worldPos: Vector3?, kind: string)
	local _ = { id, worldPos, kind }
	error("TODO(client-hud): ScreenFX.arrow")
end

return ScreenFX
