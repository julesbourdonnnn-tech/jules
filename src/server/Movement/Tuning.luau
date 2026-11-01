--!strict
-- Réglages de l'anti-triche de déplacement (Server/Util/MoveCheck), possédés par le jeu.
-- SERVEUR SEULEMENT (ServerScriptService) : ces seuils ne sont JAMAIS répliqués aux clients (un
-- tricheur qui connaît « 1,5 × vmax + 4 studs » règle sa triche juste en dessous). Ne pas les
-- déplacer dans Shared/Config (vérifié par MoveCheck_config.spec).
-- Valeurs reprises de Comet Conga (6 tours de QA, contre-audit anti-triche) ; seules les bornes du
-- monde (Center, MaxRadius) et la vitesse maximale par défaut dépendent de la carte et des
-- déplacements du jeu. Note INT-MOVE (contrat v1.2, paquet chase, seul éditeur) : bornes de Wobbleton
-- (centre (0, 0), MaxRadius 330 : murs invisibles à r = 322), monture (hausse de la racine, montée
-- permise d'après la hauteur de saut de la selle), crédit de bond (MoveCheck.grant) et historique des
-- positions validées (MoveCheck.positionAt).

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
	-- demi-hauteur de la racine 1, en R15 comme en R6). Partagée avec les portées du jeu :
	-- WorldLayout.Const.RootHeight (ZoneRules.feetY) doit rester égale (vérifié par ZoneRules.spec).
	RootHeight = 3,

	-- Monture (note INT-MOVE, MoveCheck.setRootOffset) : hausse maximale acceptée de la racine (la
	-- selle géante relève la racine de 6 studs ; au-delà, valeur bornée) et gravité du jeu (Workspace,
	-- studs/s²) pour la vitesse verticale d'un saut : v0 = √(2 × Gravity × JumpHeight).
	MaxRootOffset = 8,
	Gravity = 196.2,
	-- Hauteur de saut au-delà de laquelle la valeur est bornée (selle géante 13 + marge)
	MaxJumpHeight = 20,

	-- Bond accordé (note INT-MOVE, MoveCheck.grant, GDD §12.8) : crédit rétroactif jusqu'à GrantRetro s
	-- avant la réception du message Leap (positions et message arrivent parfois dans le désordre) ;
	-- refusé si le crédit précédent date de moins de GrantMinGap s (horloge du serveur). Valeurs par
	-- défaut du crédit (Balance.Leap.Distance, Balance.Leap.Duration : ChaseService les passe).
	GrantRetro = 0.3,
	GrantMinGap = 4,
	GrantStuds = 12,
	GrantDuration = 0.35,

	-- Historique des positions ACCEPTÉES (s) : MoveCheck.positionAt(player, t) interpole dans cet
	-- anneau (captures vérifiées à l'instant tClient du client, GDD §12.5)
	PositionHistory = 0.5,

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
		MaxClimbSpeed = 12, -- studs/s ; avec une hauteur de saut connue : max(12, √(2 g JumpHeight))
		FlagsToRewind = 3,
		FlagWindow = 5,
		RewindLockout = 3, -- s sans action après un retour
		Exemption = 3, -- après apparition ou PivotTo serveur
		MaxAltitude = 14, -- au-dessus du sol…
		AltitudeTime = 1.5, -- … pendant plus de 1,5 s
		-- Bornes du monde : distance XZ maximale au centre (Center). Wobbleton (note INT-MOVE) : centre
		-- de la place (0, 0), murs invisibles du bord à r = 322 (WorldLayout.Const.WallRadius) ; une
		-- seule valeur partout (remarque A29).
		CenterX = 0,
		CenterZ = 0,
		MaxRadius = 330,
		MinY = -5,
		StrikesForBan = 10, -- retours forcés…
		StrikeWindow = 600, -- … en 10 min → exclusion des classements
	},
}

return Tuning
