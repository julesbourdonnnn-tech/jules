--!strict
-- EventService (paquet chase) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Événements du serveur (GDD §2.4, §4.22, §4.23, §7.5) : transitions de phase par EventClock (Rush,
-- MEGA, Golden, Lune) diffusées par Signals.EventPhase et EventState ; MEGA SQUISH (objectif adapté,
-- indulgence, pressions agrégées, MegaBeat 4 Hz, paliers de bébés, MEGA MOON) ; jauge du serveur
-- (objectif 600 × max(2, N actifs), points UNIQUEMENT ici, depuis les signaux et Events.Gauge.Points :
-- une pression ne compte que PERFECT ; danse de Big Plop, WOBBLE PARTY 5 min, puis sieste de 20 min
-- sans fête, EventState.gauge.restUntil) ; joueurs ACTIFS (Server/Util/Activity, Events.Activity : N du
-- MEGA et de la jauge) ; Jelly Moon (Autel : 5 min de présence → Goutte de Lune, une par séance et
-- par compte : clé moon.lastSession) ; file des grands spectacles (≥ 20 s d'écart, place et attente
-- prévue par entrée, coupure dure à 480 s, Signals.SpectacleStarted ; héros parti avant l'éclatement :
-- spectacle effacé aussitôt) ; boosts de serveur (EconomyService.setServerBoost : payé d'abord, jamais
-- cumulés) ; Squish Party (un achat croisé PROLONGE de 600 s ; segments suivis par acheteur) ;
-- LiveOps (MessagingService, administrateurs) et commandes de développement (AdminCommand ; "clock"
-- en Studio seulement). EventState porte les interrupteurs en vigueur (features), renvoyé à chaque
-- Features.set appliqué.
-- Émet EventPhase, SpectacleStarted, MegaJoined. Remotes : MegaPress, AdminCommand ; EventState,
-- MegaBeat. Clé : moon.

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

-- Démarre la fête payée (10 min, ×2 serveur) ; pendant une fête en cours, la PROLONGE de 600 s (reçu
-- croisé : jamais refusé, aucune file en mémoire) ; segment de 600 s noté pour cet acheteur
function EventService.startSquishParty(buyer: Player, showName: boolean): boolean
	local _ = { buyer, showName }
	error("TODO(chase): EventService.startSquishParty")
end

-- Secondes de Squish Party achetées par ce joueur et pas encore jouées (≤ 600 par achat) : rendues en
-- boost personnel par ProductService au départ de l'acheteur et à la fermeture du serveur
function EventService.partyUnplayed(userId: number): number
	local _ = { userId }
	error("TODO(chase): EventService.partyUnplayed")
end

-- Joueurs sur le serveur (N)
function EventService.playerCount(): number
	error("TODO(chase): EventService.playerCount")
end

-- Joueur ACTIF (Activity.isActive, ou à Events.Activity.MegaAlertRadius du centre de la place pendant
-- l'alerte du MEGA, position validée)
function EventService.isActive(player: Player, now: number): boolean
	local _ = { player, now }
	error("TODO(chase): EventService.isActive")
end

-- N actifs (au moins Events.Activity.MinPlayers) : objectif du MEGA à l'atterrissage, objectif de la jauge
function EventService.activeCount(now: number): number
	local _ = { now }
	error("TODO(chase): EventService.activeCount")
end

-- États minutés ouverts (débogage, robot de longue durée : docs/04 §17.2 invariant 6) : « mega », « spectacle », « squishParty », « wobbleParty » ;
-- noms de StateTimeouts.names(), startedAt en Clock.now()
function EventService.openStates(): { Types.OpenState }
	error("TODO(chase): EventService.openStates")
end

return EventService
