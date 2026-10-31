--!strict
-- Réglages techniques du paquet « conga » qui n'ont pas (encore) de place dans Shared/Config.
-- Chaque valeur est nommée et sourcée ; les nombres de gameplay restent dans Config/Balance
-- (docs/04-architecture.md §1, règle 5). Candidats à un déplacement dans Balance (paquet logic).

local Tuning = {
	-- Hauteur de la HumanoidRootPart au-dessus du sol pour un personnage debout (HipHeight 2 +
	-- demi-hauteur de la racine 1, en R15 comme en R6 ; même valeur que le CongaRenderer et que la
	-- hauteur du corps des Gloomwisps). Les miettes d'autorité sont ramenées au plus à cette hauteur
	-- au-dessus du sol : les Nebbies marchent au sol, un saut ou un vol ne soulève jamais la file
	-- hors de portée verticale des coupes (Balance.Snip.MaxDy).
	RootHeight = 3,

	-- MoveCheck : durée maximale (s) passée hors de portée verticale des coupes, c'est-à-dire la
	-- racine à plus de RootHeight + Balance.Snip.MaxDy au-dessus du sol ; au-delà, chaque tick est
	-- une infraction. Un vrai saut (JumpHeight 7,2, gravité 196,2) n'y reste qu'≈ 0,36 s.
	HoverTime = 1,
}

return Tuning
