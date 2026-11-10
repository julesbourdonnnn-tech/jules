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
	-- flèches de bord d'écran (GDD v1.3 §10.2) : 2 au plus dans tous les modes (Golden, puis la créature
	-- attrapable la plus proche par priorité), seulement pour une cible à range studs au plus
	edgeArrow = { size = 72, max = 2, range = 120 },
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

-- Textes du monde (UI/WorldText, GDD v1.3 §10.2) : tout texte du monde que le joueur doit lire est un
-- BillboardGui dimensionné en Offset (px TV × UIScale), LightInfluence = 0, fond foncé translucide ou
-- contour, distance maximale fixée par usage ; jamais un texte posé au sol ni dimensionné en studs.
Layout.WorldText = {
	Text = 32, -- texte à lire (prix et niveau d'une dalle, consigne, taille d'un squishy ciblé)
	Plus = 40, -- « +N » (taille fixe à l'écran)
	Glyph = 48, -- glyphes (leçon de l'accueil au-dessus de l'objet, invites)
	MinProjected = 28, -- taille projetée minimale à TestDistance studs, aux 3 résolutions (couche d)
	TestDistance = 20,
	TileLabelDistance = 20, -- étiquette d'une dalle visible à 20 studs ou moins (le disque garde l'icône)
	Background = 0.35, -- transparence du fond foncé (opacité ≥ 0,6)
}

-- Clavier et souris (GDD v1.3 §10.4, docs/04 §14.6) : le menu est lié à KeyCode.M ET KeyCode.Semicolon
-- (sur AZERTY, la touche marquée « M » est Semicolon ; la puce affiche celle qui donne « M » par
-- GetStringForKeyCode), JAMAIS à Tab (liste des joueurs de Roblox) ; raccourcis directs des panneaux ;
-- sac à objets de Roblox coupé (StarterGui:SetCoreGuiEnabled(Backpack, false) sous pcall, nouveaux
-- essais pendant BackpackRetry s) pour que 1, 2, 3 ne servent qu'aux emotes.
Layout.Keyboard = {
	Menu = { "M", "Semicolon" }, -- noms d'Enum.KeyCode
	Panels = {
		Ranch = "G",
		Squishydex = "C",
		Objectives = "J",
		Leaderboards = "L",
		Shop = "B",
		Settings = "P",
	} :: { [string]: string },
	BackpackRetry = 10,
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
	-- v2.0 (lot B3, étape 5, D19) : cartes de la v2.0 intercalées, ordre relatif de la v1.3 inchangé
	-- (« Bienvenue dans la v2 ! » et « De retour à ton record » juste après le retour et les boops ;
	-- « Nouveau », piste, Carnet, maîtrise et étape du record après le Squishydex)
	Order = {
		"return",
		"mode",
		"postBoop",
		"booped",
		"welcomeV2",
		"regainDone",
		"objectives",
		"newObjectives",
		"dex",
		"unlockNew",
		"trackTier",
		"carnet",
		"mastery",
		"recordStep",
		"clip",
		"sleepy",
	},
}

-- Délais d'interface (GDD §10.6)
Layout.Focus.RescueAfter = 0.25 -- s : sélection vide, hors de la fenêtre ou posée en jeu : rendue
Layout.Focus.HoldMax = 60 -- s : sélection tenue pendant une fenêtre de Roblox (achat, invitation)
Layout.Focus.DoubleCloseGuard = 0.35 -- s : fermeture ignorée juste après l'ouverture
Layout.ClickTarget = { MinRadius = 32, RadiusFactor = 1.2, Hold = 4 } -- clic souris sur un squishy

-- =================================================================================================
-- Contrat v2.0 (GDD v2.0 §10.2, §10.7, §10.8 ; docs/04 §27.8) : écran Améliorations et HUD v2.0.
-- Lu seulement quand Config/Features.UpgradesScreen est ouvert. Toutes les tailles sont FIXES et
-- calculées depuis le panneau (règle 10) ; coordonnées en px TV de référence (1920 × 1080),
-- relatives au panneau quand elles sont dans Upgrades.
-- =================================================================================================
Layout.Upgrades = {
	-- zones du panneau Layout.Panel.rect (1 440 × 860) : 12 + 88 + 64 + 560 + 120 + 16 = 860
	Margin = 32, -- largeur utile 1 376
	Header = { y = 12, h = 88, title = 48 },
	Tabs = { y = 100, h = 64, text = 32 },
	Content = { y = 164, h = 560 },
	Detail = { y = 724, h = 120, text = 28, lines = 2, worstFactor = 1.5 }, -- 2 lignes au facteur 1,5
	Bottom = 16,
	-- en-tête : places fixes (largeurs réservées), de droite à gauche après la pastille Souvenir
	Coins = { w = 280, icon = 48, text = 40 },
	Confetti = { w = 200, icon = 48, text = 40 },
	Mode = { w = 200, glyph = 48, text = 40 },
	HeaderGap = 16,
	Memory = { x = 320, w = 360, h = 48, icon = 32, text = 28 }, -- x 320-680 dans le panneau
	-- 3 gabarits du composant unique UI/UpgradeCard (règle 11)
	-- onglet Conseillé : 3 cartes ; icône de 80 = pile du GDD §10.7.4 (16 → 96 ; lot B2, B2-2), écart 40
	Card = { w = 432, h = 528, gap = 40, icon = 80, title = 36, value = 40 },
	Row = { w = 1328, h = 112, step = 128 }, -- onglets Ranch, Plopettes, Atelier
	Tile = { w = 400, h = 300, icon = 120, title = 36, titleLines = 2, value = 40, margin = 16 }, -- aperçus
	-- colonnes d'une ligne : { x, w } dans la ligne
	Columns = {
		icon = { x = 16, w = 80 },
		text = { x = 112, w = 540 },
		level = { x = 668, w = 140 },
		effect = { x = 824, w = 240 },
		state = { x = 1080, w = 232 },
	},
	PreviewLine = { w = 1376, h = 120, text = 40 }, -- ligne d'explication des aperçus de renaissance
	RefusalBox = { w = 600, h = 120 }, -- boîte des refus de l'aperçu
	ConfirmButton = { w = 360, h = 112, text = 40 }, -- « Plus tard » / « Oui, Ascension ! »
	MaxInstances = 1400, -- règle 20 : budget d'instances de l'écran
}

-- HUD v2.0 (N9, N18) : rail de 8 boutons, puce « Prochain achat » ; remplacent les valeurs v1.3 du
-- HUD quand UpgradesScreen est ouvert (paquet B2 ; Layout.Hud garde la disposition de la v1.3)
Layout.HudV2 = {
	Rail = { buttons = 8, size = 80, gap = 16, icon = 48, y0 = 246, y1 = 998, w = 340, text = 36 },
	NextBuy = { x = 96, y = 342, w = 440, h = 96 } :: Rect,
	-- Rectangles RÉELS de chaque élément du HUD v2.0 (GDD §10.2, tableau de vérification, critique
	-- m13), en coordonnées d'écran 1920 × 1080 ; Contract_upgrades vérifie qu'ils sont dans la zone
	-- sûre, sans recouvrement (sauf les paires de Exclusive, jamais visibles ensemble) et hors du
	-- milieu de l'écran (Center, laissé au personnage et à ses squishies)
	Rects = {
		coins = { x = 96, y = 54, w = 440, h = 112 } :: Rect,
		fame = { x = 96, y = 178, w = 320, h = 56 } :: Rect, -- 3 s quand la Fame ou les amis changent
		menuChip = { x = 96, y = 246, w = 260, h = 80 } :: Rect,
		rail = { x = 96, y = 246, w = 340, h = 752 } :: Rect, -- à la place de la puce Menu
		nextBuy = { x = 96, y = 342, w = 440, h = 96 } :: Rect, -- cachée quand le rail est ouvert
		eventPill = { x = 680, y = 54, w = 560, h = 72 } :: Rect,
		megaBar = { x = 600, y = 138, w = 720, h = 48 } :: Rect,
		gauge = { x = 740, y = 138, w = 440, h = 48 } :: Rect, -- jauge et icône, hors MEGA
		message = { x = 460, y = 198, w = 1000, h = 112 } :: Rect, -- bannière (le message est plus petit)
		tracker = { x = 1384, y = 54, w = 440, h = 104 } :: Rect,
		status = { x = 1608, y = 170, w = 216, h = 96 } :: Rect, -- 3 indicateurs de 64, écart 12, minutes
		card = { x = 1304, y = 330, w = 520, h = 220 } :: Rect,
		special = { x = 700, y = 822, w = 520, h = 96 } :: Rect,
		target = { x = 620, y = 930, w = 680, h = 96 } :: Rect,
		dash = { x = 1728, y = 930, w = 96, h = 96 } :: Rect,
	},
	-- paires jamais visibles ensemble (le rail remplace la puce Menu et cache la puce « Prochain
	-- achat » ; la barre du MEGA remplace la jauge du serveur)
	Exclusive = { { "rail", "menuChip" }, { "rail", "nextBuy" }, { "megaBar", "gauge" } },
	Center = { x = 560, y = 330, w = 720, h = 492 } :: Rect, -- x 560-1280, y 330-822 : libre
	CalmMax = 8, -- le HUD calme montre au plus 8 éléments
}

return Layout
