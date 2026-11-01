--!strict
-- Disposition télé « 10 pieds » (GDD §10.1-§10.3) : la SEULE disposition du jeu, sur console comme
-- sur PC (manette ou clavier-souris). Contrat (architecte) : données figées.
-- Unité : « px TV » = pixels d'un écran de 1920 × 1080. UIScale = max(MinScale, min(L / 1920,
-- H / 1080)), sans plafond (1 en 1080p, 2 en 4K, 0,667 en 720p) : la taille vue du canapé ne change
-- pas. Zone sûre TV de 5 % sur TOUS les écrans : x de 96 à 1824, y de 54 à 1026.
-- Lu par l'interface (HUD, cartes, panneaux, invites, FocusGuard) et par le vérificateur de
-- disposition des specs (tests/harness/Layout, couche d du GDD §12.10) : chaque rectangle du HUD est
-- à une place fixe et deux éléments ne se recouvrent jamais, aux 3 résolutions et dans les 2 langues.
-- Config/Console (socle) porte les mêmes valeurs depuis la note INT-TV (appliquée par le contrat,
-- docs/04 §22) : UI/Root met à l'échelle avec cette règle sur tous les écrans. Le code du jeu lit CE
-- module. Les rectangles sont en coordonnées d'ÉCRAN 1920 × 1080 : dans Root.safe (dont la marge
-- intérieure est la zone sûre), un élément se place à (x − Safe.x, y − Safe.y) depuis le coin de son
-- ancrage (colonnes écartées sur les écrans plus larges).

export type Rect = { x: number, y: number, w: number, h: number } -- coin haut gauche, px TV
export type Anchor = "topLeft" | "topCenter" | "topRight" | "right" | "bottomCenter" | "bottomRight"
export type HudSlot = {
	rect: Rect, -- position par défaut en 1920 × 1080 (ancrage ci-dessous), px TV
	anchor: Anchor, -- bord de la zone sûre auquel l'élément est accroché (écrans plus larges : colonnes écartées)
	column: "left" | "center" | "right" | "bottom",
}

local Layout = {}

Layout.Reference = { X = 1920, Y = 1080 }
Layout.MinScale = 0.5
Layout.SafeMargin = 0.05
Layout.Safe = { x = 96, y = 54, w = 1728, h = 972 } :: Rect -- x 96-1824, y 54-1026

-- Résolutions vérifiées par les specs (couche d) ; plus deux formats non 16:9 (colonnes écartées)
Layout.TestResolutions = {
	{ X = 1920, Y = 1080 },
	{ X = 3840, Y = 2160 },
	{ X = 1280, Y = 720 },
}
Layout.ExtraResolutions = {
	{ X = 2560, Y = 1080 }, -- 21:9
	{ X = 1920, Y = 1200 }, -- 16:10
}

-- Tailles minimales et habituelles (px TV)
Layout.Text = {
	Min = 28, -- texte que le joueur doit lire (UITextSizeConstraint.MinTextSize)
	Body = 32,
	Button = 40,
	Title = 48,
	Banner = 56,
	Counter = 64,
}
Layout.Glyph = { Min = 48, Prompt = 64 }
Layout.Button = { MinHeight = 80, MainHeight = 96 }
Layout.Spacing = { Min = 16, Normal = 24 }
Layout.Focus = { Frame = 6, Border = 2, Grow = 1.05, Breath = 1.2 } -- cadre blanc 6 px + liseré sombre 2 px
Layout.Corner = { Min = 14, Max = 18 }
Layout.Stroke = 3
Layout.MaxCalmElements = 8 -- éléments visibles en jeu calme (GDD §10.1)

-- HUD (GDD §10.2) : rectangles en 1920 × 1080
Layout.Hud = {
	coins = { rect = { x = 96, y = 54, w = 440, h = 112 }, anchor = "topLeft", column = "left" },
	fame = { rect = { x = 96, y = 178, w = 320, h = 56 }, anchor = "topLeft", column = "left" },
	menuChip = { rect = { x = 96, y = 246, w = 260, h = 80 }, anchor = "topLeft", column = "left" },
	menuRail = { rect = { x = 96, y = 246, w = 340, h = 744 }, anchor = "topLeft", column = "left" },
	eventPill = { rect = { x = 680, y = 54, w = 560, h = 72 }, anchor = "topCenter", column = "center" },
	megaBar = { rect = { x = 600, y = 138, w = 720, h = 48 }, anchor = "topCenter", column = "center" },
	gauge = { rect = { x = 740, y = 138, w = 440, h = 40 }, anchor = "topCenter", column = "center" },
	message = { rect = { x = 460, y = 198, w = 1000, h = 112 }, anchor = "topCenter", column = "center" },
	goalTracker = { rect = { x = 1384, y = 54, w = 440, h = 104 }, anchor = "topRight", column = "right" },
	status = { rect = { x = 1584, y = 170, w = 240, h = 96 }, anchor = "topRight", column = "right" },
	card = { rect = { x = 1304, y = 330, w = 520, h = 220 }, anchor = "right", column = "right" },
	specialChip = { rect = { x = 700, y = 822, w = 520, h = 96 }, anchor = "bottomCenter", column = "bottom" },
	targetCard = { rect = { x = 620, y = 930, w = 680, h = 96 }, anchor = "bottomCenter", column = "bottom" },
	leap = { rect = { x = 1728, y = 930, w = 96, h = 96 }, anchor = "bottomRight", column = "bottom" },
} :: { [string]: HudSlot }

-- Contenu de chaque élément (GDD §10.2) : tailles de texte et de glyphe (px TV)
Layout.HudContent = {
	coins = { icon = 80, amount = 56, rate = 32 },
	fame = { text = 32 },
	menuChip = { glyph = 48, text = 40 },
	menuRail = { button = { w = 340, h = 96 }, gap = 12, icon = 56, text = 36, maxButtons = 7 },
	eventPill = { text = 36 },
	megaBar = { text = 28 },
	gauge = { icon = 40, bar = { w = 400, h = 28 } },
	message = { bannerTitle = 48, bannerLine = 32, toast = 32, toastSize = { w = 760, h = 88 } },
	goalTracker = { ring = 72, title = 32, value = 28 },
	status = { icon = 64, gap = 12, max = 3, minutes = 28 },
	card = { title = 40, text = 32, glyph = 48, seconds = 8 },
	specialChip = { glyph = 48, text = 40, clapRing = 8 },
	targetCard = { name = 36, details = 28 },
	leap = { glyph = 64 },
	edgeArrow = { size = 72 },
}

-- Colonnes (vérification sans recouvrement, GDD §10.2) ; le milieu reste libre pour le personnage
Layout.Columns = {
	left = { x = 96, y = 54, w = 440, h = 936 },
	center = { x = 460, y = 54, w = 1000, h = 256 },
	right = { x = 1304, y = 54, w = 520, h = 496 },
	bottom = { x = 620, y = 822, w = 1204, h = 204 },
	free = { x = 460, y = 330, w = 840, h = 492 },
} :: { [string]: Rect }

-- Invites dans le monde (UI/Prompt, GDD §10.2) : jamais deux invites sur la même touche, 2 au plus
Layout.Prompt = {
	Plate = { w = 300, h = 88 },
	MainGlyph = 64,
	MainText = 40,
	SecondGlyph = 48,
	SecondText = 32,
	MaxPrompts = 2,
}

-- Fenêtres (GDD §10.3)
Layout.Panel = {
	rect = { x = 240, y = 110, w = 1440, h = 860 } :: Rect,
	header = 96,
	title = 48,
	tabHeight = 72,
	tabText = 32,
	cell = { w = 208, h = 232 },
	columns = 6,
	visibleRows = 2.5, -- la demi-rangée montre qu'on peut défiler
	buttonHeight = { min = 80, max = 96 },
	close = { w = 80, h = 80 },
	toggle = { w = 120, h = 64 },
}

Layout.Cards = {
	ModeButton = { w = 440, h = 120, text = 40 }, -- carte du choix Rush / Cozy
	ReturnButton = { w = 360, h = 112, text = 40 }, -- « Super ! »
	NonBlockingSeconds = 8,
	-- Ordre de la file des cartes (une seule à la fois, GDD §10.3). « booped » : carte non bloquante
	-- « Un de tes squishies s'enfuit ! » avec « Continuer » et « Pas ce joueur » (RefuseBooper), jamais
	-- un Toast (un Toast ne prend jamais la sélection). Cards ne lie aucune touche : △ / croix ↓ ouvre
	-- le menu (InputController → PanelController.toggleMenu), dont l'entrée « ! » rouvre la carte.
	Order = {
		"return",
		"mode",
		"postBoop",
		"booped",
		"objectives",
		"newObjectives",
		"dex",
		"clip",
		"sleepy",
	},
}

-- Délais d'interface (GDD §10.6)
Layout.Focus.RescueAfter = 0.25 -- s : sélection vide, hors de la fenêtre ou posée en jeu : rendue
Layout.Focus.HoldMax = 60 -- s : sélection tenue pendant une fenêtre de Roblox (achat, invitation)
Layout.Focus.DoubleCloseGuard = 0.35 -- s : fermeture ignorée juste après l'ouverture
Layout.ClickTarget = { MinRadius = 32, RadiusFactor = 1.2, Hold = 4 } -- clic souris sur un squishy

return Layout
