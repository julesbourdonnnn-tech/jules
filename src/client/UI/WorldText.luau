--!strict
-- WorldText (paquet client-hud) — STUB du contrat (docs/04 §13.5, contrat v1.2). Implémenter =
-- remplacer chaque error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les
-- signatures.
-- Textes du monde lisibles à 3 m sur une télé (GDD v1.3 §10.2, remarque C2-12) : tout texte du monde
-- que le joueur DOIT lire (prix et niveau d'une dalle, glyphe et mot de la leçon de l'accueil au-dessus
-- de l'objet, « +N », taille d'un squishy ciblé, invites) est un BillboardGui dimensionné en pixels
-- fixes (Offset) multipliés par l'échelle d'interface de UI/Root (UIScale), jamais en studs ni posé
-- au sol : texte ≥ Layout.WorldText.Text (32 px TV), « +N » Layout.WorldText.Plus (40), glyphes ≥
-- Layout.WorldText.Glyph (48), LightInfluence = 0, fond foncé translucide (Layout.WorldText.Background)
-- ou contour 3 px, distance maximale fixée par usage (dalle : 20 studs). Invites : position bornée à
-- la zone sûre de 5 %. Réserve d'étiquettes (aucune création en rafale).
-- Module-outil sans Init ni Start (comme UI/Juice) : appelé par UI/Prompt (client-hud),
-- RanchRenderer (étiquettes des dalles, leçon de l'accueil) et VFXController (« +N ») ; il ne dépend
-- que de UI/Root, UI/Theme, Config/Layout.
-- Spec (couche d) : Console_hud / Layout_hud vérifient que la taille projetée de chaque texte du
-- monde est ≥ Layout.WorldText.MinProjected (28 px TV) à 20 studs, en 1920 × 1080, 3840 × 2160 et
-- 1280 × 720.

export type Kind = "text" | "plus" | "glyph"

export type Options = {
	kind: Kind, -- taille en px TV : Layout.WorldText.Text, Plus ou Glyph
	maxDistance: number, -- studs (BillboardGui.MaxDistance)
	studsOffset: Vector3?, -- décalage au-dessus de l'objet (StudsOffsetWorldSpace)
	alwaysOnTop: boolean?,
	name: string?,
}

local WorldText = {}

-- BillboardGui en Offset × UIScale, LightInfluence 0, fond foncé translucide, accroché à `adornee`
function WorldText.create(adornee: Instance, options: Options): BillboardGui
	local _ = { adornee, options }
	error("TODO(client-hud): WorldText.create")
end

-- Texte affiché (déjà traduit par Prefs.t ; nombres par Logic/BigNumber)
function WorldText.setText(gui: BillboardGui, text: string)
	local _ = { gui, text }
	error("TODO(client-hud): WorldText.setText")
end

-- Taille en px TV d'une sorte de texte (32, 40 ou 48)
function WorldText.pixelSize(kind: Kind): number
	local _ = { kind }
	error("TODO(client-hud): WorldText.pixelSize")
end

-- Taille du texte projetée à l'écran, en px TV (écran de `viewport` pixels) : specs de disposition
function WorldText.projectedPx(gui: BillboardGui, viewport: Vector2): number
	local _ = { gui, viewport }
	error("TODO(client-hud): WorldText.projectedPx")
end

-- Coin haut gauche d'une plaque de `size` pixels ramené dans la zone sûre de 5 % (invites)
function WorldText.clampToSafe(screen: Vector2, size: Vector2, viewport: Vector2): Vector2
	local _ = { screen, size, viewport }
	error("TODO(client-hud): WorldText.clampToSafe")
end

-- Réapplique l'échelle à toutes les étiquettes vivantes (résolution changée)
function WorldText.rescale()
	error("TODO(client-hud): WorldText.rescale")
end

-- Rend l'étiquette à la réserve
function WorldText.release(gui: BillboardGui)
	local _ = { gui }
	error("TODO(client-hud): WorldText.release")
end

return WorldText
