--!strict
-- CongaService — paquet « conga » (STUB du contrat : docs/04-architecture.md §6 et §11.13).
-- DERNIER service initialisé : il orchestre le tick fixe de 10 Hz et possède les files.
-- Responsabilités :
--   * tick : accumulateur sur UNE connexion RunService.Heartbeat, pas fixe Balance.Tick.Step (0,1 s),
--     au plus MaxCatchUp (3) pas par image ; ordre EXACT des étapes et appels : §6 du contrat
--   * miettes par joueur : trail (Trail.new(170, 0,5)) pour l'autorité, netTrail (Trail.new(170, 1,0,
--     firstSeq)) pour le réseau, numérotation contiguë par slot entre propriétaires successifs ;
--     poussées seulement si MoveCheck valide le tick ; remise à zéro sur saut ≥ 40 studs
--   * captures : joueurs avec place libre × SpawnService.query (rayon Attrait + 0,75, |Δy| ≤ 6,
--     Snip Rush ×1,5) ; le plus proche gagne, égalité → ordre tiré au hasard à chaque tick ;
--     file pleine → Feedback "feedback.lineFull" au plus toutes les 5 s ; plafond 1 500 captures/h
--     (au-delà : 5 min de suspension + flags.lbBanned) ; Signals.Caught ; bannières Légendaire+
--   * coupes : joueurs × files puis Gloomwisps × files (EventService.wispSweeps), SnipRules
--     (blockReason puis findCut, escorte via CrewService.escortersOf, port sûr via WorldLayout) ;
--     détache cutFrom(k, n) … n, Nebbies libres (SpawnService.spawnLoose silent, priorité victime),
--     immunités, recharges, Second Souffle (+4 pendant 3 s), Snip Rush (Attrait ×1,5, +5 Stardust par
--     Nebby plafonnée, pas de Stardust si le coupeur est sous bouclier) ; SnipEvent ; Signals.Snipped ;
--     Analytics SnipDealt / SnipReceived / SnipByInput / PostSnipQuit
--   * parades : boîte de la porte de SON Nid (WorldLayout.inGateBox), et anneau de la Balise quand
--     EventService.beaconOpen() ; Glow = EconomyService.paradeGlow ; AtlasService.addNebbies ;
--     LineEvent "bank" ; Signals.Parade ; Méga Parade (≥ 30) ; QuestService.onSafeMoment ;
--     EventService.onBeaconParade
--   * WalkSpeed (seul propriétaire de Humanoid.WalkSpeed) : Formulas.walkSpeed (Foulée, ralenti
--     au-delà des Guard Links, Comète ×0,85, Dash +10 pendant 1 s, Second Souffle +4) ;
--     MoveCheck.noteSpeed ; remote Dash() 3/s (profil chargé, pas porteur, recharge serveur) →
--     Signals.Dashed, attribut Player DashReadyAt
--   * mort / réinitialisation : file détachée (priorité au propriétaire, sans Second Souffle) ;
--     départ : détachée sans priorité ; LineEvent "clear" avec loose ; EventService.dropComet
--   * temps d'escorte (Signals.EscortTime), joueurs actifs (SpawnService/EventService.setActivePlayers)
--   * diffusion : PathStream (PathCodec, non fiable, 10 Hz, 2 points répétés), LineEvent groupé
--     par tick, SnipEvent ; remotes RequestWorld() 1/2 s → WorldSnapshot, RequestPath(slot 1-12) 4/s
--     → PathSnapshot (200 derniers points) ; WorldSnapshot à chaque arrivée
--   * remote SetInputType(kind 1-3) 1/5 s (aide tactile +0,3 aux coupes, champ analytique)
--   * MoveCheck : 3 infractions en 5 s → retour (PivotTo), 3 s sans capture/coupe/parade, attribut
--     « Unstable » ; flags.strikes ; 10 retours en 10 min → flags.lbBanned ; Signals.MoveViolation
--   * pose le crochet EconomyService.setLineBanker(forceParade) dans Init
-- GDD : §4.5-§4.8, §4.16, §4.17, §12.1, §12.3, §12.4, §12.7, §14.3.
-- Dépendances : TOUS les services précédents, Util/MoveCheck, Logic/*, Config/*, Signals,
-- Util/Notify, Util/RateLimit, Util/Analytics, Shared/Util/Clock.

local Types = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Types)

local CongaService = {}

function CongaService.Init() end

function CongaService.Start() end

-- Un pas fixe de tick (exposé pour les tests : Clock.freeze + CongaService.tick)
function CongaService.tick(_now: number)
	error("TODO(conga): CongaService.tick")
end

function CongaService.lineLength(_player: Player): number
	error("TODO(conga): CongaService.lineLength")
end

function CongaService.lineCodes(_player: Player): { Types.NebbyCode }
	error("TODO(conga): CongaService.lineCodes")
end

function CongaService.lineCapacity(_player: Player): number
	error("TODO(conga): CongaService.lineCapacity")
end

-- Positions serveur des nœuds 1 … n (abscisse HeadGap + (i − 1) × Spacing sur trail)
function CongaService.nodePositions(_player: Player): { Vector3 }
	error("TODO(conga): CongaService.nodePositions")
end

-- Encaisse immédiatement la file (parade normale, sans test de porte) ; Glow crédité
function CongaService.forceParade(_player: Player): number
	error("TODO(conga): CongaService.forceParade")
end

-- Joueur actif (≥ 4 studs parcourus pendant les 60 dernières s)
function CongaService.isActive(_player: Player): boolean
	error("TODO(conga): CongaService.isActive")
end

function CongaService.activeCount(): number
	error("TODO(conga): CongaService.activeCount")
end

-- Type d'entrée déclaré (1 tactile, 2 clavier-souris, 3 manette)
function CongaService.inputType(_player: Player): number
	error("TODO(conga): CongaService.inputType")
end

function CongaService.worldSnapshot(_player: Player): Types.WorldSnapshotPayload
	error("TODO(conga): CongaService.worldSnapshot")
end

return CongaService
