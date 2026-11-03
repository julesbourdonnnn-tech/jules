--!strict
-- Bus de signaux internes du serveur (repris de Comet Conga, étendu par le contrat : docs/04 §7).
-- Les services communiquent « vers le haut » de l'ordre d'initialisation (Main.server ORDER) par
-- ces signaux : un service peut émettre ou écouter n'importe lequel, quel que soit son rang, alors
-- qu'un appel direct d'API n'est permis que vers un service initialisé AVANT lui.
-- Chaque signal a UN émetteur (commentaire « émis par ») ; les abonnés se branchent dans Start().
-- Les handlers s'exécutent chacun dans leur propre thread, lancé AUSSITÔT (task.spawn, Shared/Util/
-- Signal) : un handler sans yield finit avant que l'émetteur reprenne. Jamais de yield long dans un
-- handler qui mute un profil sans revérifier DataService.get(player). Un handler protège son travail
-- (une erreur dans un thread de handler est comptée par DiagnosticsService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)

export type PressInfo = {
	uid: string,
	perfect: boolean,
	streak: number, -- série PERFECT après cette pression
	visitor: Player?, -- pet-sitting : le visiteur qui a pressé chez le propriétaire (sinon nil)
}

export type CatchInfo = {
	kind: Types.CreatureKind,
	species: number,
	rarity: number,
	mutation: number,
	ownerId: number, -- propriétaire du squishy en fuite (0 sinon)
	hero: boolean, -- le propriétaire a attrapé son propre squishy
	byLeap: boolean, -- capture à l'atterrissage d'un bond
	babyUid: string, -- bébé créé chez l'attrapeur ("" si aucun : Héros, plafond atteint)
}

local Signals = {
	-- =========================================================================================
	-- Socle
	-- =========================================================================================
	-- Émis par RanchService (placement à l'apparition, poussée d'un intrus) : déplacement imposé
	-- par le serveur → ChaseService appelle MoveCheck.reset (exemption des paquets « en vol »)
	ServerMoved = Signal.new() :: Signal.Signal<Player>,
	-- Émis par ChaseService (MoveCheck.step) : infraction de déplacement (player, infractions de la
	-- session) → analytique (MoveViolation), attribut « Unstable » (icône « connexion instable »)
	MoveViolation = Signal.new() :: Signal.Signal<Player, number>,
	-- Tous (via Notify.banner) → CommunityService (file des bannières : priorité, durée, débit
	-- par joueur source, nouveaux avant l'étape 9) qui la diffuse
	BannerRequested = Signal.new() :: Signal.Signal<Types.BannerKind, { [string]: any }, Player?>,

	-- =========================================================================================
	-- Cycle de vie, monde
	-- =========================================================================================
	-- Émis par RanchService, une fois par session : profil chargé (crochets onPrepare passés) et ranch
	-- attribué, dès que le premier personnage est placé ET AU PLUS TARD StateTimeouts « playerReady »
	-- (15 s) après, même si le placement a échoué (il est réessayé à part) → QuestService (étape 1,
	-- sessions), CommunityService (amis), EventService (EventState), LeaderboardService (état),
	-- DiagnosticsService (contexte, « bonjour » du panneau aux administrateurs), ChaseService
	PlayerReady = Signal.new() :: Signal.Signal<Player, number>,
	-- Émis par RanchService (remote RequestWorld, ou trou dans la suite d'un client) : renvoyer son
	-- état à ce joueur → EventService (EventState), ChaseService (créatures actives)
	WorldRequested = Signal.new() :: Signal.Signal<Player>,
	-- Émis par DataService (note INT-REPAIR) : réparations faites par ProfileRepair au chargement
	-- → DiagnosticsService (compte « ProfileRepaired:<champ> »)
	ProfileRepaired = Signal.new() :: Signal.Signal<Player, { string }>,

	-- =========================================================================================
	-- Ranch et collection
	-- =========================================================================================
	-- Émis par SquishyService (Press et pet-sitting) → QuestService (stats, objectifs), EventService
	-- (jauge : perfect seulement chez soi, petSit au visiteur ; Events.Gauge.Points.press = 0). « Plus
	-- serviable » ne se compte PAS ici (une pression au-delà des plafonds n'est pas récompensée) : voir
	-- PetSitRewarded.
	Pressed = Signal.new() :: Signal.Signal<Player, PressInfo>,
	-- Émis par EconomyService : dalle achetée (tile, nouveau niveau) → QuestService (étape 3, objectif)
	TileBought = Signal.new() :: Signal.Signal<Player, string, number>,
	-- Émis par EconomyService : Pot encaissé (montant, auto) → QuestService (étape 6, objectif)
	PotCollected = Signal.new() :: Signal.Signal<Player, number, boolean>,
	-- Émis par SquishyService : un squishy entre dans la collection (uid, source) ; source :
	-- "vat" | "twin" | "runaway" | "golden" | "wild" | "rush" | "mega" | "gift" | "lucky" | "lunar" |
	-- "demo" | "fusion" | "hero" → QuestService (tampons du Squishydex, objectif « Grande éclosion »)
	SquishyObtained = Signal.new() :: Signal.Signal<Player, string, string>,
	-- Émis par SquishyService : naissance dans la Cuve (uid, rareté) → QuestService, EventService (jauge)
	Hatched = Signal.new() :: Signal.Signal<Player, string, number>,
	-- Émis par SquishyService : étape de fusion (uid obtenu, étape k du combo) → QuestService,
	-- EventService (jauge), LeaderboardService (« Meilleur combo »)
	Fused = Signal.new() :: Signal.Signal<Player, string, number>,
	-- Émis par SquishyService : un squishy quitte la collection (uid, raison "sell" | "release" |
	-- "fusion" | "tidy") → RushService et CommunityService (clôtures), ChaseService
	SquishyRemoved = Signal.new() :: Signal.Signal<Player, string, string>,

	-- =========================================================================================
	-- Poursuites, BOOP RUSH, événements
	-- =========================================================================================
	-- Émis par ChaseService : capture accordée (attrapeur, info) → QuestService, EventService (jauge),
	-- LeaderboardService (« Meilleure capture », « Plus généreux » pour le propriétaire)
	Caught = Signal.new() :: Signal.Signal<Player, CatchInfo>,
	-- Émis par ChaseService : joueur « de près » d'une capture (sorte "golden" | "rush") →
	-- QuestService (« Course dorée »), EventService (jauge)
	NearCatch = Signal.new() :: Signal.Signal<Player, string>,
	-- Émis par RushService : boop réussi (boopeur, propriétaire, uid, angle d'éloignement en
	-- radians) → ChaseService (crée la fuite), QuestService (stats, objectif)
	Booped = Signal.new() :: Signal.Signal<Player, Player, string, number>,
	-- Émis par ChaseService : fin d'une fuite du Rush (propriétaire, uid, issue "hero" | "baby" |
	-- "returned" | "cozy" | "left", attrapeur ou nil) → RushService (protections, carte d'après le
	-- premier boop), QuestService (stats)
	EscapeEnded = Signal.new() :: Signal.Signal<Player, string, string, Player?>,
	-- Émis par RushService : mode effectif changé (rush ?) → ChaseService (passage en Cozy : fuites
	-- en cours rentrées aussitôt)
	ModeChanged = Signal.new() :: Signal.Signal<Player, boolean>,
	-- Émis par EventService : transition de phase (sorte, phase, index) ; sortes et phases :
	-- "rush" (siren, start, end), "mega" (warn, land, end), "golden" (spawn, end), "moon" (start,
	-- end), "party" (start, end), "wild" (wave) → RushService, ChaseService, SplorchService, QuestService
	EventPhase = Signal.new() :: Signal.Signal<string, string, number>,
	-- Émis par EventService : un grand spectacle commence (sorte "splorch" | "dance", userId,
	-- Clock.now() de départ) → SplorchService (Grand Splorch de ce héros)
	SpectacleStarted = Signal.new() :: Signal.Signal<string, number, number>,
	-- Émis par EventService : fin du MEGA, participation (joueur, points, réussite) → QuestService
	MegaJoined = Signal.new() :: Signal.Signal<Player, number, boolean>,
	-- Émis par SplorchService : Grand Splorch appliqué au profil (héros, nouveau R, bébés-cadeaux
	-- donnés aux autres joueurs) → QuestService (étape 11, objectif), LeaderboardService (« Plus
	-- généreux » + cadeaux), RushService (fin de l'attente), EventService (jauge : splorch)
	Splorched = Signal.new() :: Signal.Signal<Player, number, number>,

	-- =========================================================================================
	-- Rétention, social
	-- =========================================================================================
	-- Émis par QuestService : Meilleur Ami nourri (jours au total) → EventService (jauge)
	Fed = Signal.new() :: Signal.Signal<Player, number>,
	-- Émis par QuestService : étape d'accueil atteinte (numéro) → ChaseService, CommunityService
	OnboardingStep = Signal.new() :: Signal.Signal<Player, number>,
	-- Émis par QuestService : nouveaux tampons ou badges d'étoiles du Squishydex (nombre gagné) →
	-- LeaderboardService (« Plus de tampons » de la semaine)
	Stamped = Signal.new() :: Signal.Signal<Player, number>,
	-- Émis par QuestService (intention UiSeen, une fois par écran et par session) : écran vu par le
	-- joueur ("objectives", "modeCard", "postBoop", "booped", "shop", "dex", "leaderboards") →
	-- RushService ("modeCard" : délai de 20 s de la carte du choix, RushModeChosen = −1 sans réponse)
	UiSeen = Signal.new() :: Signal.Signal<Player, string>,
	-- Émis par CommunityService : signal de la croix joué (sorte 1-3) → QuestService (objectif)
	Emoted = Signal.new() :: Signal.Signal<Player, number>,
	-- Émis par CommunityService : réglage changé (clé, valeur) → tout service qui en dépend
	-- (LeaderboardService : hideName réécrit le drapeau « caché » de ses valeurs de la semaine)
	SettingChanged = Signal.new() :: Signal.Signal<Player, string, any>,
	-- Émis par CommunityService : nombre d'amis Roblox présents de ce joueur changé (arrivée ou départ
	-- d'un ami) → QuestService (QuestCtx.friendOnServer, objectif 12, stats.lastFriendDay)
	FriendsChanged = Signal.new() :: Signal.Signal<Player, number>,
	-- Émis par CommunityService : pression de pet-sitting RÉCOMPENSÉE (visiteur, propriétaire, compte pour
	-- « Plus serviable »), donc dans les plafonds du jour (caps.petSit du visiteur, caps.petSitIn du
	-- propriétaire) ; le 3e argument est vrai si caps.petSitBy[propriétaire] du visiteur était encore sous
	-- Balance.CapsPerFriend.petSit (20 par ami et par jour, EconomyService.consumeFriendCap) →
	-- LeaderboardService (« Plus serviable » : seulement si le 3e argument est vrai), QuestService
	PetSitRewarded = Signal.new() :: Signal.Signal<Player, Player, boolean>,

	-- =========================================================================================
	-- Contrat v2.0 (GDD v2.0, docs/04 §27.4) : jamais émis tant que les interrupteurs sont coupés
	-- =========================================================================================
	-- Émis par SplorchService après Prestige.apply (sorte "splorch" | "petit" | "ascend", r avant,
	-- r après, A après) → QuestService (piste, cartes « Nouveau »), HelperService (reprise), RanchService
	-- (attributs), LeaderboardService (Livre des records), analytique
	PrestigeApplied = Signal.new() :: Signal.Signal<Player, string, number, number, number>,
	-- Émis par EconomyService.buyUpgrade (id, niveau avant, niveau après, monnaie) → QuestService
	-- (Carnet : stats.upgradesBought, objectifs), RanchService (paliers et cascade), analytique
	UpgradeBought = Signal.new() :: Signal.Signal<Player, string, number, number, string>,
	-- Émis par EconomyService.addConfetti et buyUpgrade (écart signé, source) → QuestService (Défi
	-- « Gagne 20 Confettis »), analytique (ConfettiEarned)
	ConfettiChanged = Signal.new() :: Signal.Signal<Player, number, string>,
	-- Émis par SplorchService au premier passage d'un Record R (nouveau bestR) → QuestService (carte
	-- « Nouveau : … », unlocksSeen), CommunityService (habillages et cosmétiques gagnés), RanchService
	RecordReached = Signal.new() :: Signal.Signal<Player, number>,
	-- Émis par HelperService : pression d'une Plopette accordée (numéro de la Plopette, uid, pièces) →
	-- EconomyService (crédit, source « Helper »), analytique (HelperCoinsShare) ; jamais la jauge, les
	-- objectifs ni les classements
	HelperPressed = Signal.new() :: Signal.Signal<Player, number, string, number>,
}

return Signals
