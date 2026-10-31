--!strict
-- EventService — paquet « events » (STUB du contrat : docs/04-architecture.md §11.8).
-- Propriétaire de l'état des événements de serveur (mémoire) : météo, Grande Comète, Nuit de la
-- Balise, Starfall Frenzy, Nuit d'Or, Gloomwisps, Starfall Saturday, boosts de serveur, LiveOps.
-- Responsabilités :
--   * transitions de phase pilotées par Logic/EventClock(Clock.now()) dans step(now) ; bannières
--     (Notify.banner) ; Signals.EventPhase ; SpawnService.setModifiers à chaque changement ;
--     EconomyService.setServerBoostUntil à chaque changement de boost
--   * Comète : alerte −8 s, impact au point déterministe, ramassage (premier joueur valide à ≤ 4 studs,
--     pas en Zen), vol « chat perché » (non-équipier, test balayé ≤ 4 studs ; nouveau porteur
--     immunisé 2 s, ancien interdit 4 s ; port sûr et bouclier ne protègent PAS), encaissement à la
--     porte de son Nid (Nebby → AtlasService.addNebbies "comet" + 120 s de revenu passif),
--     explosion à +75 s (5 Épiques libres dans le Cratère, 1 par joueur, SpawnService.spawnLoose),
--     participations (≥ 3 s : +50 ; ≤ 20 studs à la fin : +15 et 30 s de revenu ; équipiers de
--     l'encaisseur : +25), chute si le porteur part, meurt ou passe en Zen (dropComet)
--   * Balise : alerte −15 s, trêve, barre de serveur (1 point par Nebby encaissé à l'anneau),
--     objectif Formulas.beaconGoal (miséricorde après 2 et 3 échecs), réussite IMMÉDIATE quand la
--     barre est pleine → Frenzy 60 s puis Nuit d'Or 5 min ; échec à la fin : +15 par contributeur ;
--     réussite : +40 par contributeur, bannière du meilleur contributeur ; Signals.BeaconResult
--   * Gloomwisps : nombre Formulas.wispCount (aucun pendant la Balise et Starfall), trajets
--     SeededPath (seed, t0), balayages pour les coupes (CongaService), éclatement à ≤ 4,5 studs
--     (+10 Stardust plafonnée, 20 s de revenu ; réapparition 10 s plus tard sur une nouvelle seed)
--   * Starfall Saturday : Rainbow continu, comètes toutes les 3 min, boost 20 min, présence ≥ 5 min
--     → 1 Nebby vedette Starborn envoyé au Nid à la fin
--   * boosts de serveur : une seule ligne de temps ×2 (Nuit d'Or, Starfall, Glow Party, LiveOps) ;
--     queueGlowParty prolonge depuis max(now, fin actuelle)
--   * LiveOps : remote AdminCommand (UserIds de Data/Admins seulement) → MessagingService
--     « LiveOps » → tous les serveurs ; attribut Player « Admin »
--   * EventState : état complet envoyé à tous à chaque changement (flush, au plus 1 par tick)
-- GDD : §2.4, §4.15.1-§4.15.5, §4.10 (boosts), §7.6, §9.4, §14.3.
-- Dépendances : DataService, NestService, EconomyService, AtlasService, SpawnService,
-- Logic/EventClock, Logic/SeededPath, Logic/Formulas, Logic/Trail, Logic/WorldLayout, Config/*,
-- Data/Admins, Signals, Util/Notify, Util/RateLimit, Util/Analytics, Shared/Util/Clock.

local Types = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Types)

local EventService = {}

export type WispSweep = { id: number, from: Vector3, to: Vector3 }

function EventService.Init() end

function EventService.Start() end

-- Étape 3 du tick : transitions de phase, positions des Gloomwisps
function EventService.step(_now: number)
	error("TODO(events): EventService.step")
end

-- Étape 6 du tick : ramassage, vol, encaissement, explosion de la Comète
function EventService.stepComet(_now: number, _actors: { Types.Actor })
	error("TODO(events): EventService.stepComet")
end

-- Étape 7 : balayages des Gloomwisps actifs depuis le tick précédent (vide pendant la trêve)
function EventService.wispSweeps(_now: number): { WispSweep }
	error("TODO(events): EventService.wispSweeps")
end

-- Un Gloomwisp vient de couper une file (« miam ! », comptage analytique WispSnip)
function EventService.onWispSnip(_wispId: number, _victim: Player, _count: number)
	error("TODO(events): EventService.onWispSnip")
end

-- Étape 8 : Gloomwisps éclatés par les joueurs
function EventService.stepWisps(_now: number, _actors: { Types.Actor })
	error("TODO(events): EventService.stepWisps")
end

-- Étape 12 : envoie EventState si l'état a changé
function EventService.flush()
	error("TODO(events): EventService.flush")
end

-- Trêve de la Balise (aucune coupe, joueurs ni Gloomwisps)
function EventService.isTruce(): boolean
	error("TODO(events): EventService.isTruce")
end

-- L'anneau de la Balise sert-il de porte de parade ?
function EventService.beaconOpen(): boolean
	error("TODO(events): EventService.beaconOpen")
end

-- Parade à l'anneau de la Balise : `count` points pour la barre
function EventService.onBeaconParade(_player: Player, _count: number)
	error("TODO(events): EventService.onBeaconParade")
end

function EventService.isCarrier(_player: Player): boolean
	error("TODO(events): EventService.isCarrier")
end

function EventService.carrier(): Player?
	error("TODO(events): EventService.carrier")
end

-- Le porteur lâche la Comète (départ, mort, Zen) : elle retombe à sa dernière position valide
function EventService.dropComet(_player: Player)
	error("TODO(events): EventService.dropComet")
end

-- Forme de la météo active (nil = aucune ou Meteor Shower)
function EventService.weatherForm(): number?
	error("TODO(events): EventService.weatherForm")
end

function EventService.serverBoostActive(): boolean
	error("TODO(events): EventService.serverBoostActive")
end

-- Glow Party : prolonge le boost ×2 de serveur ; retourne la nouvelle fin
function EventService.queueGlowParty(_buyer: Player, _seconds: number): number
	error("TODO(events): EventService.queueGlowParty")
end

-- Secondes de Glow Party restantes (bouton masqué au-delà de Balance.GlowParty.HideAbove)
function EventService.glowPartyRemaining(): number
	error("TODO(events): EventService.glowPartyRemaining")
end

-- Poussé par CongaService (joueurs actifs) au plus une fois par seconde
function EventService.setActivePlayers(_n: number)
	error("TODO(events): EventService.setActivePlayers")
end

-- Exécute une commande LiveOps localement (après validation ou réception MessagingService)
function EventService.runLiveOps(_command: string)
	error("TODO(events): EventService.runLiveOps")
end

function EventService.snapshot(): Types.EventStatePayload
	error("TODO(events): EventService.snapshot")
end

return EventService
