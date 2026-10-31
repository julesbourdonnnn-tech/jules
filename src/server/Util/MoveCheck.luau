--!strict
-- MoveCheck — paquet « conga » (STUB du contrat : docs/04-architecture.md §11.14).
-- Contrôle de déplacement serveur (GDD §12.7), état par joueur en mémoire, SANS service Roblox :
-- CongaService lui fournit positions, vitesses et hauteur du sol ; testable sous Lune.
-- Règles (Config/Balance.MoveCheck) :
--   * déplacement XZ autorisé par tick = vmax × dt × 1,5 + 4, vmax = WalkSpeed serveur maximal des
--     0,5 dernières s (noteSpeed) ; montée verticale ≤ 12 studs/s ; chute libre ignorée
--   * altitude > sol + 14 pendant plus de 1,5 s, r > 182 ou Y < −5 → retour immédiat
--   * une infraction SIGNALE seulement (verdict "flag" : ce tick ne peut ni attraper, ni couper, ni
--     encaisser, ni voler la Comète) ; 3 infractions en 5 s → "rewind" vers la dernière position
--     valide, puis 3 s de restriction (isRestricted)
--   * exemptions : 3 s après reset (apparition, PivotTo serveur)
--   * jamais d'accusation : l'interface affiche « connexion instable » (ton neutre)
-- GDD : §12.7, §14.3 (MoveViolation), §14.4 (marges réglables).
-- Dépendances : Config/Balance.

local MoveCheck = {}

export type Verdict = "ok" | "flag" | "rewind"

-- Nouvelle référence de position (apparition, PivotTo serveur) : exemption de Balance.MoveCheck.Exemption s
function MoveCheck.reset(_player: Player, _pos: Vector3, _now: number)
	error("TODO(conga): MoveCheck.reset")
end

-- WalkSpeed serveur appliqué à `now` (historique de SpeedWindow s)
function MoveCheck.noteSpeed(_player: Player, _walkSpeed: number, _now: number)
	error("TODO(conga): MoveCheck.noteSpeed")
end

-- Vérifie le déplacement du tick ; "rewind" fournit la position de retour
function MoveCheck.step(
	_player: Player,
	_pos: Vector3,
	_dt: number,
	_now: number,
	_groundY: number
): (Verdict, Vector3?)
	error("TODO(conga): MoveCheck.step")
end

-- Captures, coupes et parades interdites (3 s après un retour)
function MoveCheck.isRestricted(_player: Player, _now: number): boolean
	error("TODO(conga): MoveCheck.isRestricted")
end

function MoveCheck.lastValid(_player: Player): Vector3?
	error("TODO(conga): MoveCheck.lastValid")
end

-- Infractions de la session (analytique MoveViolation)
function MoveCheck.violations(_player: Player): number
	error("TODO(conga): MoveCheck.violations")
end

-- Retours forcés dans la fenêtre StrikeWindow (exclusion des classements à StrikesForBan)
function MoveCheck.recentRewinds(_player: Player, _now: number): number
	error("TODO(conga): MoveCheck.recentRewinds")
end

function MoveCheck.clear(_player: Player)
	error("TODO(conga): MoveCheck.clear")
end

return MoveCheck
