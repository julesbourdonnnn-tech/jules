--!strict
-- ChaseService (paquet chase) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Tick de 10 Hz du serveur (le seul Heartbeat serveur, docs/04 §6) et poursuites (GDD §4.11, §4.12,
-- §4.21, §12.5, §12.8) : MoveCheck à chaque tick (budget d'action, retours, attribut « Unstable » ;
-- sol = WorldLayout.supportY(position), jamais un Blockcast),
-- créatures en fuite personnelles (toutes les 60 s, 50 avec Froggy), Golden Wobbler, Wild Wobblers
-- (partagés et personnels), fuites du Rush (sur Signals.Booped), démonstration de Big Plop, bonds
-- (Leap : recharge 4 s, MoveCheck.noteSpeed(GrantSpeed) pendant 0,35 s, capture à l'atterrissage
-- calculée par LeapRules), captures (Catch : position validée contre SeededPath, tolérance 1,5 stud),
-- récompenses (bébés, Héros, retours, « de près »), ChaseEvent groupé à 4 Hz, fin des créatures par
-- délai, anti-triche (strikes, exclusion des classements jusqu'à la fin de la semaine suivante).
-- Émet MoveViolation, Caught, NearCatch, EscapeEnded. Remotes : Leap, Catch ; ChaseEvent.
-- Clés : flags, golden.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)

local ChaseService = {}

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function ChaseService.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function ChaseService.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Tick complet (docs/04 §6) ; chaque étape sous pcall, erreur comptée par Diagnostics
function ChaseService.tick(now: number)
	local _ = { now }
	error("TODO(chase): ChaseService.tick")
end

-- Acteurs du dernier tick (positions validées)
function ChaseService.actors(): { [Player]: Types.TickActor }
	error("TODO(chase): ChaseService.actors")
end

-- Créatures actives
function ChaseService.active(): { [number]: Types.ChaseSpawn }
	error("TODO(chase): ChaseService.active")
end

-- Ce squishy est en fuite
function ChaseService.isEscaping(owner: Player, uid: string): boolean
	local _ = { owner, uid }
	error("TODO(chase): ChaseService.isEscaping")
end

-- Toutes les fuites de ce propriétaire rentrent aussitôt (Cozy, départ)
function ChaseService.returnEscapes(owner: Player, reason: string)
	local _ = { owner, reason }
	error("TODO(chase): ChaseService.returnEscapes")
end

-- Recharge du bond restante
function ChaseService.leapCooldownLeft(player: Player, now: number): number
	local _ = { player, now }
	error("TODO(chase): ChaseService.leapCooldownLeft")
end

-- États minutés ouverts (débogage, robot de longue durée : docs/04 §17.2 invariant 6) : « runaway », « escape », « wild », « golden », « demo » (créatures), « leap » (bonds), « unstable » ;
-- noms de StateTimeouts.names(), startedAt en Clock.now()
function ChaseService.openStates(): { Types.OpenState }
	error("TODO(chase): ChaseService.openStates")
end

return ChaseService
