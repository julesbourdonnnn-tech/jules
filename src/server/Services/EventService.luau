--!strict
-- EventService (paquet chase) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Événements du serveur (GDD §2.4, §4.22, §4.23, §7.5) : transitions de phase par EventClock (Rush,
-- MEGA, Golden, Lune) diffusées par Signals.EventPhase et EventState ; MEGA SQUISH (objectif adapté,
-- indulgence, pressions agrégées, MegaBeat 4 Hz, paliers de bébés, MEGA MOON) ; jauge du serveur
-- (objectif 500 × max(2, N), points UNIQUEMENT ici, depuis les signaux et Events.Gauge.Points, danse
-- de Big Plop, WOBBLE PARTY 5 min) ; Jelly Moon (Autel : 5 min de
-- présence → Goutte de Lune) ; file des grands spectacles (≥ 20 s d'écart, Signals.SpectacleStarted) ;
-- boosts de serveur (EconomyService.setServerBoost : payé d'abord, jamais cumulés) ; Squish Party ;
-- LiveOps (MessagingService, administrateurs) et commandes de développement (AdminCommand ; "clock"
-- en Studio seulement). EventState porte les interrupteurs en vigueur (features), renvoyé à chaque
-- Features.set appliqué.
-- Émet EventPhase, SpectacleStarted, MegaJoined. Remotes : MegaPress, AdminCommand ; EventState,
-- MegaBeat. Clés : aucune.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)

local EventService = {}

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function EventService.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function EventService.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Tick : phases, MEGA (agrégation, battement), jauge, fêtes, file des spectacles, Autel
function EventService.step(now: number, actors: { [Player]: Types.TickActor })
	local _ = { now, actors }
	error("TODO(chase): EventService.step")
end

-- État diffusé (dernier envoyé)
function EventService.state(): Types.EventStatePayload
	error("TODO(chase): EventService.state")
end

-- Rush en cours
function EventService.rushActive(): boolean
	error("TODO(chase): EventService.rushActive")
end

-- Séance de Jelly Moon en cours
function EventService.moonActive(): boolean
	error("TODO(chase): EventService.moonActive")
end

-- Mode BOOP RUSH "events" : Lune ou fête d'administrateur en cours
function EventService.eventBoopActive(): boolean
	error("TODO(chase): EventService.eventBoopActive")
end

-- Points de jauge (bornés, ignorés pendant la fête)
function EventService.addGauge(points: number)
	local _ = { points }
	error("TODO(chase): EventService.addGauge")
end

-- Place dans la file ; rend le Clock.now() de départ prévu
function EventService.enqueueSpectacle(kind: "splorch" | "dance", userId: number): number
	local _ = { kind, userId }
	error("TODO(chase): EventService.enqueueSpectacle")
end

-- Retire de la file (départ du joueur avant son tour)
function EventService.cancelSpectacle(userId: number)
	local _ = { userId }
	error("TODO(chase): EventService.cancelSpectacle")
end

-- Une Squish Party peut commencer aussitôt
function EventService.canStartParty(): boolean
	error("TODO(chase): EventService.canStartParty")
end

-- Démarre la fête payée (10 min, ×2 serveur)
function EventService.startSquishParty(buyer: Player, showName: boolean): boolean
	local _ = { buyer, showName }
	error("TODO(chase): EventService.startSquishParty")
end

-- Joueurs sur le serveur (N)
function EventService.playerCount(): number
	error("TODO(chase): EventService.playerCount")
end

-- États minutés ouverts (débogage, robot de longue durée : docs/04 §17.2 invariant 6) : « mega », « spectacle », « squishParty », « wobbleParty » ;
-- noms de StateTimeouts.names(), startedAt en Clock.now()
function EventService.openStates(): { Types.OpenState }
	error("TODO(chase): EventService.openStates")
end

return EventService
