--!strict
-- Réglages de l'anti-triche de déplacement (Server/Util/MoveCheck), possédés par le jeu.
-- SERVEUR SEULEMENT (ServerScriptService) : ces seuils ne sont JAMAIS répliqués aux clients (un
-- tricheur qui connaît « 1,5 × vmax + 4 studs » règle sa triche juste en dessous). Ne pas les
-- déplacer dans Shared/Config (vérifié par MoveCheck_config.spec).
-- Valeurs reprises de Comet Conga (6 tours de QA, contre-audit anti-triche) ; seules les bornes du
-- monde (Center, MaxRadius) et la vitesse maximale par défaut dépendent de la carte et des
-- déplacements du jeu : à régler par l'architecte quand Wobbleton et la monture existent.

local Tuning = {
	-- Tick du service qui appelle MoveCheck.step (s) et nombre maximal de pas rattrapés au même
	-- instant après un accroc du serveur. La durée d'un tick pour le budget d'action est bornée à
	-- TickStep × MaxCatchUp : un accroc n'est jamais une rafale, un trou plus long (personnage
	-- absent sans réinitialisation) ne devient jamais un crédit de bond.
	TickStep = 0.1,
	MaxCatchUp = 3,

	-- Vitesse supposée (studs/s) tant qu'aucun WalkSpeed n'a été noté (noteSpeed) : le maximum
	-- atteignable en jeu (marche, monture, bond). Comet Conga : 16 + 10 (Foulée) + 10 (Dash) + 4.
	-- À régler : WalkSpeed 16 aujourd'hui, monture « 1,4× plus vite » et bond R2 à venir.
	DefaultMaxSpeed = 40,

	-- Hauteur de la HumanoidRootPart au-dessus du sol pour un personnage debout (HipHeight 2 +
	-- demi-hauteur de la racine 1, en R15 comme en R6).
	RootHeight = 3,

	-- Portée verticale des actions (studs) : une racine à plus de ActionReachY au-dessus ou au-dessous
	-- de la hauteur debout (sol + RootHeight) est hors de portée des actions au sol (Comet Conga :
	-- portée verticale des coupes). Vol bas : racine > sol + RootHeight + ActionReachY ; racine
	-- enfouie : racine < surface + RootHeight − ActionReachY.
	ActionReachY = 4,

	-- Durée maximale (s) passée hors de portée verticale des actions ; au-delà, chaque tick est une
	-- infraction. Un vrai saut (JumpHeight 7,2, gravité 196,2) ne passe qu'≈ 0,36 s au-dessus.
	HoverTime = 1,

	-- Racine à plus de MaxBelowGround studs SOUS la surface du sol → hors du monde (passe-muraille),
	-- retour immédiat comme sous MoveCheck.MinY. Même un personnage couché garde la racine au-dessus.
	MaxBelowGround = 2,

	-- Contrôle de déplacement (marges réglables). Lu par Util/MoveCheck (exposé en MoveCheck.Config
	-- pour les tests) et par le service qui applique les sanctions (exclusion des classements).
	MoveCheck = {
		Margin = 1.5, -- déplacement XZ autorisé = vmax × dt × Margin + Slack
		Slack = 4,
		SpeedWindow = 0.5, -- vmax = WalkSpeed max des 0,5 dernières s
		MaxClimbSpeed = 12,
		FlagsToRewind = 3,
		FlagWindow = 5,
		RewindLockout = 3, -- s sans action après un retour
		Exemption = 3, -- après apparition ou PivotTo serveur
		MaxAltitude = 14, -- au-dessus du sol…
		AltitudeTime = 1.5, -- … pendant plus de 1,5 s
		-- Bornes du monde : distance XZ maximale au centre (Center). Comet Conga : île de rayon 182.
		-- À régler sur la carte de Wobbleton.
		CenterX = 0,
		CenterZ = 0,
		MaxRadius = 1000,
		MinY = -5,
		StrikesForBan = 10, -- retours forcés…
		StrikeWindow = 600, -- … en 10 min → exclusion des classements
	},
}

return Tuning
