--!strict
-- Réglages techniques du paquet « conga » qui n'ont pas (encore) de place dans Shared/Config.
-- Chaque valeur est nommée et sourcée ; les nombres de gameplay restent dans Config/Balance
-- (docs/04-architecture.md §1, règle 5). Candidats à un déplacement dans Balance (paquet logic).

local Tuning = {
	-- Hauteur de la HumanoidRootPart au-dessus du sol pour un personnage debout (HipHeight 2 +
	-- demi-hauteur de la racine 1, en R15 comme en R6 ; même valeur que le CongaRenderer et que la
	-- hauteur du corps des Gloomwisps). Les miettes d'autorité sont posées à cette hauteur au-dessus
	-- du sol analytique (WorldLayout.groundY) : les Nebbies marchent au sol, un saut, un vol ou une
	-- racine enfouie (passe-muraille) ne déplacent jamais la file hors de portée verticale des coupes
	-- (Balance.Snip.MaxDy), ni hors de vue des autres joueurs.
	RootHeight = 3,

	-- MoveCheck : durée maximale (s) passée hors de portée verticale des coupes, c'est-à-dire la
	-- racine à plus de Balance.Snip.MaxDy au-dessus ou au-dessous de la hauteur debout
	-- (sol + RootHeight) ; au-delà, chaque tick est une infraction. Un vrai saut (JumpHeight 7,2,
	-- gravité 196,2) ne passe qu'≈ 0,36 s au-dessus.
	HoverTime = 1,

	-- MoveCheck : racine à plus de MaxBelowGround studs SOUS la surface du sol → hors du monde
	-- (passe-muraille), retour immédiat comme sous Balance.MoveCheck.MinY. Debout, la racine est à
	-- sol + RootHeight ; même un personnage couché garde la racine au-dessus du sol.
	MaxBelowGround = 2,

	-- Sonde du sol réel (CongaService, workspace:Blockcast vers le bas depuis la racine) : la
	-- hauteur du sol passée à MoveCheck tient compte de ce qui porte vraiment le personnage (stèle du
	-- tableau, tête d'un autre joueur, poteaux…), que la formule de WorldLayout.groundY ignore.
	-- Pavé carré de FloorProbeWidth studs de côté (empreinte 2 × 1 de la racine, quelle que soit
	-- son orientation, + marge : un personnage tient au bord d'une stèle de 0,8 stud), épaisseur
	-- FloorProbeThickness, portée RootHeight + Snip.MaxDy + FloorProbeMargin sous la racine (un
	-- appui plus bas ne porte pas une racine encore à portée des coupes).
	FloorProbeWidth = 2.5,
	FloorProbeThickness = 0.2,
	FloorProbeMargin = 1,
}

return Tuning
