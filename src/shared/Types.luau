--!strict
-- Types partagés. Aucun code exécutable : ce module ne renvoie qu'une table vide ; on l'importe pour
-- ses `export type`.
--   local Types = require(Shared.Types)
--   local function f(payload: Types.FeedbackPayload) … end
-- Registre partagé : ajouts ciblés autorisés (jamais de suppression ni de renommage).
-- Contrat de Raise a Squishy (docs/04 §9, §10) : les charges utiles des remotes sont des tables
-- SOIT tableaux séquentiels SOIT dictionnaires à clés chaînes (jamais mixtes ni à trous : règle de
-- sérialisation des remotes Roblox, vérifiée par tests/harness/Wire), sans NaN ni infini.

-- =============================================================================================
-- Généraux (socle)
-- =============================================================================================

export type InputKind = number -- 1 tactile, 2 clavier-souris, 3 manette (Client/Util/Platform)
export type Lang = "auto" | "en" | "fr"

-- Réglages sauvegardés du profil (Data/Schema, Config/Settings)
export type ProfileSettings = {
	reducedMotion: boolean,
	lowGraphics: boolean,
	music: boolean,
	sfx: boolean,
	vibration: boolean,
	lang: Lang,
	hideName: boolean,
	receiveGifts: boolean,
	clips: boolean,
	emoteLeft: string, -- "bravo" | "bellyFlop" | "crown" ; v2.0 (lot A4) : + emotes de Config/Settings.emoteLeft.values
	partyShowName: boolean,
}

-- =============================================================================================
-- Réseau : charges utiles serveur → client (socle)
-- =============================================================================================

-- DataPatch(patch, removed, entries?) : 3e argument, entrées d'une grande table du profil
-- (DataService.markDirtyEntry), ex. { squishies = { set = { u12 = rec }, del = { "u3" } } }.
export type DataEntryOps = { set: { [string]: any }, del: { string } }
export type DataPatchEntries = { [string]: DataEntryOps }

-- Feedback : refus et confirmations pour un joueur (Server/Util/Notify.feedback)
export type FeedbackTone = "info" | "success" | "warning" | "error" | "reward"
export type FeedbackPayload = {
	key: string, -- clé de localisation (« feedback.* »)
	vars: { [string]: any },
	tone: FeedbackTone,
}

-- Celebrate : moments personnels (Server/Util/Notify.celebrate). Sortes : CelebrateKind ci-dessous
-- (liste fermée, docs/04 §10.3, vérifiée par Contract_game) ; données de chaque sorte : types
-- Celebrate<Sorte> plus bas (section « Célébrations »). `data` reste un dictionnaire à clés chaînes.
export type CelebrateKind =
	"press"
	| "tile"
	| "pot"
	| "hatch"
	| "fusion"
	| "catch"
	| "ownerReturn"
	| "returnedBigger"
	| "booped"
	| "boopDone"
	| "splorch"
	| "giftRain"
	| "megaResult"
	| "lunarDrop"
	| "luckyDrop"
	| "dexNew"
	| "objectiveDone"
	| "objectivesCard"
	| "newObjectives"
	| "plopDay"
	| "onboarding"
	| "sleepy"
	| "return"
	| "unlock"
	| "saddle"
	| "purchase"
	| "clapCount"
	| "fanfare"
	| "photo"
	| "testError"
	-- v2.0 (lot I, étape 2, INT-V2-CELEBRATE : sortes v2.0 fusionnées ici, plus de type à part)
	| "petitSplorch"
	| "ascend"
	| "tier"
	| "unlock2"
	| "confetti"
	| "trackTier"
	| "carnet"
	| "mastery"
	| "regainDone"
	| "recordStep"
	| "welcomeV2"
export type CelebratePayload = {
	kind: CelebrateKind,
	data: { [string]: any },
}

-- Banner : bannière d'écran. Sortes et priorités : Config/Events.Banners.Priority (1 = plus haute).
export type BannerKind = string
export type BannerPayload = {
	kind: BannerKind,
	args: { [string]: any }, -- userId, name (ou alias si nom caché), n, species, mutation, oneIn…
	priority: number, -- 1 = plus haute
	personal: boolean?, -- envoyé à un seul joueur
}

-- =============================================================================================
-- Squishies (GDD §4.3, §12.6)
-- =============================================================================================

export type SpeciesId = number -- Config/Species (1 … 26 au lancement, une ligne par semaine ensuite)
export type MutationId = number -- 0 = aucune, 1 … 9 (Config/Mutations)
export type RarityId = number -- 1 … 7 (Config/Rarities)
export type Uid = string -- base 36 de profile.nextUid, 8 caractères au plus ; unique PAR PROFIL seulement
export type SquishyLocation = "pen" | "pool" | "dodo" | "mail"

-- Ligne d'un squishy dans profile.squishies[uid] (sauvegardée). Taille à l'instant t (enclos ou
-- Bassin) : z + (G(t) − zg), où G est la croissance cumulée du ranch (profile.growth, Formulas.G) ;
-- dans la Boîte à dodo ou aux Lettres, la taille est figée à z (zg ignoré).
export type SquishyRecord = {
	s: SpeciesId,
	m: MutationId,
	st: number, -- étoiles 0 … 5
	z: number, -- taille à la marque (≥ 1, ≤ Balance.Numbers.Max)
	zg: number, -- croissance cumulée G du ranch à la marque
	bf: number, -- emplacement de Meilleur Ami 0 … 3 (0 = aucun)
	lk: boolean, -- verrou
	o: string, -- tenue portée (Config/Cosmetics) ou ""
	at: SquishyLocation,
	b: number, -- naissance (Clock.unix()) : « né il y a moins de 60 s » ne vient pas à la clôture
	-- Clock.day() du dernier bonus de croissance du Rush (Héros + 1 h, retour seul + 30 min, GDD v1.3
	-- §4.21.3) : au plus un par squishy et par jour UTC (SquishyService.growFor) ; 0 = jamais
	gd: number,
}

-- Squishy visible des autres joueurs (enclos et Bassin seulement), RanchSnapshot / RanchPatch
export type PublicSquishy = {
	s: SpeciesId,
	m: MutationId,
	st: number,
	z: number,
	zg: number,
	at: SquishyLocation, -- "pen" | "pool"
	bf: number,
	o: string,
	ready: number, -- Clock.now() où la recharge de pression finit (0 = prêt)
}

-- Croissance cumulée du ranch (profile.growth) : G(t) = G + g × (t − t) tant que g ne change pas
export type Growth = { G: number, g: number, t: number }

export type TileKey = "snack" | "decor" | "pens" | "cozyBed"
export type Tiles = { snack: number, decor: number, pens: number, cozyBed: boolean, seen: number }

export type ModeState = {
	rush: boolean,
	chosen: boolean,
	changedAt: number, -- Clock.unix()
	cardShown: boolean,
	postBoopCardShown: boolean,
}

export type ObjectiveEntry = { id: number, p: number, done: boolean, claimed: boolean }

-- =============================================================================================
-- Monde : ranchs publics (RanchSnapshot / RanchPatch, GDD §12.5)
-- =============================================================================================

export type RanchMode = "rush" | "cozy"

-- État public d'un ranch (tous les clients le reçoivent). Clé de table : numéro du ranch en chaîne
-- ("1" … "16"), jamais un tableau à trous.
export type RanchPublic = {
	slot: number,
	userId: number, -- 0 = ranch libre
	name: string, -- nom d'affichage, ou "" si caché (le client écrit l'alias « Squishy Fan #NNNN »)
	hidden: boolean,
	R: number,
	fame: number,
	day: number, -- jours de Plop au total (« Jour 42 »)
	mode: RanchMode,
	shield: boolean, -- bouclier débutant (bulle « bouclier » sur un ranch en mode Rush)
	boopable: boolean, -- badge rose « boop » (mode Rush, hors bouclier)
	tiles: Tiles,
	vat: boolean, -- Cuve construite (accueil)
	pool: boolean, -- Bassin construit (accueil)
	vatFill: number, -- Clock.now() où la goutte en cours tombe (0 = arrêtée : « Plein ! »)
	growth: Growth,
	carry: Uid, -- squishy porté ("" = rien)
	ride: Uid, -- monture montée ("" = à pied)
	saddle: number, -- selle gagnée 0 … 3
	waiting: Uid, -- squishy en attente de Grand Splorch ("" = aucun)
	theme: string,
	flag: string,
	title: string,
	saddleColor: string,
	trail: string,
	-- silhouette au-dessus du ranch ; TOUJOURS présent (un champ nil ne voyage pas dans un RanchPatch,
	-- remarque A27) : s = 0 = aucune silhouette (ranch libre, enclos vides)
	best: { s: SpeciesId, m: MutationId, z: number, zg: number },
}

export type RanchSnapshotPayload = {
	seq: number, -- numéro de suite PAR DESTINATAIRE (un trou → RequestWorld)
	ranches: { [string]: RanchPublic },
	squishies: { [string]: { [Uid]: PublicSquishy } }, -- [slot] → enclos et Bassin
}

export type SquishyOp = {
	op: "add" | "remove" | "update",
	slot: number,
	uid: Uid,
	rec: PublicSquishy?, -- add / update
}

export type RanchPatchPayload = {
	seq: number,
	ranches: { [string]: { [string]: any } }, -- champs de RanchPublic qui ont changé
	ops: { SquishyOp },
}

-- Clôture (Rush ou pet-sitting) : squishies du ranch `slot` posés à la clôture côté rue. Effacer :
-- RanchService.setFence(slot, {}, maRaison) n'efface que si la raison actuelle est la sienne ; ""
-- est réservé à RanchService (ranch libéré). Après la fin du Rush, CommunityService réapplique le
-- pet-sitting à son step suivant (remarque A25).
export type FencePayload = {
	slot: number,
	uids: { Uid }, -- vide : clôture libérée
	reason: "rush" | "petsit" | "",
}

-- =============================================================================================
-- Créatures et poursuites (GDD §4.11, §4.21, §12.5)
-- =============================================================================================

export type CreatureKind = "runaway" | "escape" | "wild" | "wildPersonal" | "golden" | "demo"

-- Apparition d'une créature : le client calcule pos(t) avec Logic/SeededPath (même code que le serveur)
export type ChaseSpawn = {
	id: number, -- 1 … 65535, unique tant que la créature vit
	kind: CreatureKind,
	species: SpeciesId,
	mutation: MutationId,
	size: number,
	stars: number,
	ownerSlot: number, -- 0 = sans propriétaire (Wild, Golden)
	booperSlot: number, -- 0 = aucun (fuites du Rush seulement)
	uid: Uid, -- squishy d'origine (fuite du Rush) ou ""
	path: "escape" | "hop", -- SeededPath.escape (rues) ou SeededPath.hopAround (fuite personnelle)
	seed: number,
	t0: number, -- Clock.now() du départ
	startNode: number, -- nœud du graphe des rues (escape) ; 0 pour hop
	awayAngle: number, -- radians (premier bond, escape)
	center: { x: number, z: number }, -- centre du sautillement (hop) ; départ (escape)
	speed: number, -- studs/s au départ
	duration: number, -- s ; à t0 + duration la créature disparaît chez le client même sans `finish`
	personal: boolean, -- visible et attrapable par un seul joueur
}

export type ChaseFinish = {
	id: number,
	reason: "caught" | "returned" | "expired",
	bySlot: number, -- attrapeur (0 = personne)
	t: number,
}

export type ChaseEventPayload = {
	spawns: { ChaseSpawn },
	finishes: { ChaseFinish },
}

-- =============================================================================================
-- Événements (EventState, MegaBeat, BoopState, GDD §12.7)
-- =============================================================================================

-- Phases calculées par Logic/EventClock (pur, identique serveur et client)
export type RushPhase = { active: boolean, index: number, sirenAt: number, startsAt: number, endsAt: number }
export type MegaPhase = {
	active: boolean,
	index: number,
	warnAt: number,
	landsAt: number,
	endsAt: number, -- fin de la pression (landsAt + PressTime)
	burstEndsAt: number,
	moon: boolean,
}
export type GoldenPhase = { active: boolean, index: number, spawnAt: number, endsAt: number }
export type MoonPhase = { active: boolean, session: number, startsAt: number, endsAt: number }
export type NextEvent = { kind: "rush" | "mega" | "golden" | "moon", at: number }

-- kind "ascend" (v2.0, lot A4) : Jelly Ascend dans la file comme un Grand Splorch (Events.Spectacles
-- .ascend : 10 s, coupure 12 s) ; jamais dans la file tant que l'interrupteur JellyAscend est coupé
export type SpectacleEntry = {
	kind: "splorch" | "dance" | "ascend",
	userId: number, -- héros (0 pour la danse)
	startAt: number, -- Clock.now() prévu
	slot: number, -- ranch du héros (0 pour la danse)
	position: number, -- place dans la file (1 = prochain)
	-- attente prévue en s à l'envoi : position × Events.SpectacleGap + reste du grand spectacle en cours
	-- (Rush, MEGA, Grand Splorch, danse) ; recalculée à chaque changement (suivi du HUD « 2e · ≈ 0:40 »)
	eta: number,
}

export type SpectacleCurrent = {
	kind: "splorch" | "dance" | "ascend",
	userId: number,
	startedAt: number,
	-- application au profil : Grand Splorch startedAt + Balance.Splorch.BurstAt ; Ascension (v2.0)
	-- startedAt + Balance.Ascend.BurstAt
	burstAt: number,
	endsAt: number,
	flyer: { s: SpeciesId, m: MutationId, st: number, z: number }?,
	level: number, -- R atteint (titre « GRAND SPLORCH III »)
}

-- Interrupteurs de Config/Features en vigueur SUR LE SERVEUR (docs/04 §10.2, §12.2). Les clients ne
-- lisent jamais Config/Features pour un événement : bannières, pastille du prochain événement,
-- éclairage, costumes, clips et rapports d'erreur se règlent sur WorldStateController.event().features.
-- EventService renvoie EventState à chaque Features.set qu'il applique (LiveOps, AdminCommand).
export type EventFeatures = {
	boopRush: string, -- "on" | "events" | "off"
	megaSquish: boolean,
	golden: boolean, -- Features.GoldenWobbler
	jellyMoon: boolean,
	gauge: boolean, -- Features.ServerGauge
	clips: boolean,
	costume: string, -- Features.Costumes ("" = aucun)
	diagnostics: boolean, -- false : ErrorReporter n'envoie plus rien
	-- v2.0 (lot B4, INT-B4-AMBIENCE) : présent (true) seulement quand l'interrupteur Ambience est ouvert
	-- (directeur d'ambiance et éclairage unifié côté client) ; absent sinon : charge de la v1.3 inchangée
	ambience: boolean?,
	-- v2.0 (lot B3, INT-B3-FEATURES) : interrupteurs v2 OUVERTS que le client doit connaître pour ne rien
	-- montrer ni envoyer d'un système coupé (règle (1) du §27.3), pris dans la liste fixe RecordR,
	-- JellyAscend, PetitSplorch, Confetti, Workshop, Carnet, WeeklyTrack, Mastery, RanchSkins, DecoPerso,
	-- Hearts, Personalities, PhotoMode (les deux derniers : lot B5, INT-B5-FEATURES) ; présent seulement
	-- quand au moins un d'eux est ouvert et ne contient que les ouverts (= true) ; absent sinon : charge
	-- de la v1.3 inchangée. Lu côté client par UI/MetaFlags (écrans) et World/Flags (rendu) seulement
	v2: { [string]: boolean }?,
}

export type EventStatePayload = {
	rush: { active: boolean, index: number, endsAt: number, nextAt: number, moonBoopable: boolean },
	mega: {
		phase: "idle" | "warn" | "press" | "burst",
		index: number,
		landsAt: number,
		endsAt: number,
		target: number,
		points: number,
		species: SpeciesId,
		moon: boolean,
		result: "" | "success" | "fail",
	},
	golden: { active: boolean, id: number, endsAt: number },
	moon: { active: boolean, session: number, endsAt: number, nextAt: number },
	-- restUntil : fin de la sieste de Big Plop (Clock.now(), 0 = aucune) : jarre grise, « Big Plop se
	-- repose mm:ss » ; les points continuent de compter, aucune fête avant la fin (GDD v1.3, §4.23)
	gauge: { points: number, target: number, partyUntil: number, restUntil: number },
	boost: { kind: "" | "wobble" | "squish" | "admin", untilT: number, byName: string },
	spectacle: { current: SpectacleCurrent?, queue: { SpectacleEntry } },
	features: EventFeatures,
	offset: number, -- Clock.setOffset du serveur (commandes de développement) : le client l'applique
	-- v2.0 (lot A4), visuels seulement, ABSENTS tant que leur interrupteur est coupé (charge utile de la
	-- v1.3 inchangée) : météo de la place (Weather : kind = index de Events.Weather.Kinds, endsAt =
	-- Clock.unix() de fin de la fenêtre) ; place en fête (Fete : level 0 à 5)
	weather: { kind: number, endsAt: number }?,
	fete: { level: number }?,
}

export type MegaBeatPayload = { points: number, target: number, presses: number, t: number }

export type BoopStatePayload = {
	booperId: number,
	ownerId: number,
	uid: Uid,
	endsAt: number, -- Clock.now() de fin prévue (2,5 s ou 5 s, peut changer en cours)
	state: "hold" | "done" | "cancel",
}

-- Maintiens mesurés par le serveur pour l'anneau du client : bol de Plop (QuestService, 2 s) et attente
-- sur une dalle (RanchService, Balance.Tiles.DwellSeconds) ; tile = clé de la dalle ("" pour le bol)
export type HoldStatePayload = { kind: "feed" | "tile", endsAt: number, active: boolean, tile: string }

export type EmoteShowPayload = { userId: number, kind: number, emote: string }
export type ClapPromptPayload = { heroId: number, endsAt: number }

-- =============================================================================================
-- Classements, Diagnostics
-- =============================================================================================

export type LeaderboardCategory = "stamps" | "combo" | "catchScore" | "helpful" | "generous"
-- name = "" : nom caché par le joueur (hideName), inconnu ou non résolu → le client écrit l'alias
-- « Squishy Fan #NNNN » (name.alias, Hash.alias(userId)) ; jamais le nom d'un joueur qui l'a caché
export type LeaderboardRow = { rank: number, userId: number, name: string, value: number }
export type LeaderboardPayload = {
	week: number,
	boards: {
		[string]: { -- LeaderboardCategory
			top: { LeaderboardRow }, -- top 10 mondial (lu toutes les 120 s)
			server: { LeaderboardRow }, -- ce serveur, en direct
			mine: number, -- ma valeur de la semaine
			minePrev: number, -- semaine dernière
			myServerRank: number, -- 0 = pas classé
		},
	},
}

export type DiagEntry = {
	key: string, -- hachage court du texte normalisé + script
	kind: number, -- 1 erreur, 2 avertissement
	text: string, -- texte normalisé (nombres → #, noms → <joueur>)
	source: "server" | "client",
	count: number,
	players: number, -- joueurs touchés
	first: number, -- Clock.unix()
	last: number,
}

export type DiagSample = { key: string, text: string, trace: string, ctx: string, at: number }

export type DiagnosticsSnapshot = {
	-- 0 « bonjour » (vide, envoyé aux administrateurs à PlayerReady : rend le panneau visible),
	-- 1 Ce serveur, 2 Mon client (le client complète avec ErrorReporter.entries/stats), 3 Aujourd'hui
	tab: number,
	server: {
		placeVersion: number,
		utc: number,
		uptime: number,
		players: number,
		tickAvgMs: number,
		tickMaxMs: number,
		memoryMb: number,
		timedOut: number, -- états fermés par leur délai (StateTimedOut)
	},
	entries: { DiagEntry },
	samples: { DiagSample }, -- 3 au plus par clé
	today: { DiagEntry }, -- totaux de tous les serveurs depuis 00:00 UTC (onglet 3)
}

-- =============================================================================================
-- Écrans de données (Celebrate)
-- =============================================================================================

-- Celebrate "return" (écran de retour, GDD §7.2)
export type ReturnScreenData = {
	seconds: number, -- absence comptée (bornée à la limite hors ligne)
	uid: Uid, -- squishy montré (Meilleur Ami n° 1, sinon le plus gros)
	species: SpeciesId,
	grew: number, -- + taille pendant l'absence
	pot: number, -- + pièces dans le Pot
	splorchReady: boolean,
	nearlyReady: boolean, -- le plus gros a atteint Balance.Offline.StopAt × objectif (« Presque prêt ! »)
}

-- Aperçu du Grand Splorch (calculé par le client à partir du profil répliqué, mêmes formules
-- que le serveur : Logic/Formulas.splorchPreview)
export type SplorchPreview = {
	ready: boolean,
	target: number,
	biggest: number,
	level: number, -- R après le Grand Splorch
	unlocks: { string }, -- clés de texte des déblocages (Balance.Splorch.Unlocks)
	coinsLost: number,
	-- OBSOLÈTE (contrat v1.2 : paquets de pièces retirés, plus de 2e confirmation) : jamais lu par le
	-- client ; logic arrête de le remplir (Formulas.splorchPreview)
	recentBuy: boolean?,
	nextTarget: number,
	defaultFlyer: Uid,
}

-- =============================================================================================
-- Serveur : acteur du tick (docs/04 §6)
-- =============================================================================================

-- État minuté ouvert d'un service (API de débogage X.openStates(), docs/04 §17.2 invariant 6) :
-- name ∈ StateTimeouts.names() ; le robot de longue durée vérifie StateTimeouts.expired(name,
-- startedAt, now) == false pour chacun, à chaque tick
export type OpenState = { name: string, startedAt: number, player: Player? }

-- Joueur chargé et vivant au tick courant : position VALIDÉE par MoveCheck et droit d'agir
export type TickActor = {
	player: Player,
	slot: number, -- ranch (0 = aucun)
	pos: Vector3, -- dernière position valide (MoveCheck.lastValid) ; jamais la racine brute du client
	canAct: boolean, -- verdict "ok", pas de rafale, pas de restriction (MoveCheck.canAct)
	riding: boolean,
	-- hausse de la racine de la monture (MoveCheck.rootOffset, 0 à pied) : pieds = ZoneRules.feetY(pos.Y,
	-- rootOffset) pour les écarts verticaux des portées (GDD v1.3, §12.5, §12.8)
	rootOffset: number,
}

-- =============================================================================================
-- Célébrations : données de chaque sorte (CelebratePayload.data, docs/04 §10.3)
-- =============================================================================================

export type CelebratePress = { uid: Uid, coins: number, perfect: boolean, streak: number, petsit: boolean }
export type CelebrateTile = { tile: TileKey, level: number }
export type CelebratePot = { coins: number, auto: boolean }
export type CelebrateHatch = {
	uid: Uid,
	species: SpeciesId,
	rarity: RarityId,
	mutation: MutationId,
	oneIn: number,
	isNew: boolean,
	scripted: boolean,
	at: SquishyLocation, -- "pen", ou "dodo" quand les enclos sont pleins (bulle « Dodo » sur la Cuve)
}
export type CelebrateFusion = { uid: Uid, step: number, stars: number, coins: number }
export type CelebrateCatch = {
	kind: CreatureKind,
	species: SpeciesId,
	mutation: MutationId,
	uid: Uid,
	coins: number,
	hero: boolean,
	byLeap: boolean,
}
export type CelebrateOwnerReturn = {
	uid: Uid,
	species: SpeciesId,
	coins: number,
	catcherId: number,
	catcherName: string, -- "" si caché
	firstBoop: boolean,
}
export type CelebrateReturnedBigger = { uid: Uid, species: SpeciesId }
export type CelebrateBooped = { uid: Uid, species: SpeciesId, booperId: number }
export type CelebrateBoopDone = { ownerId: number, uid: Uid }
-- short = version courte du spectacle pour ce spectateur (GDD v1.3, §4.15) : ni capsule, ni secousse,
-- ni vibration, ni APPLAUDIR ; le héros a toujours short = false
export type CelebrateSplorch = {
	userId: number,
	level: number,
	flyer: { s: SpeciesId, m: MutationId, st: number, z: number },
	startedAt: number,
	burstAt: number,
	endsAt: number,
	short: boolean,
}
export type CelebrateGiftRain = {
	heroId: number,
	heroName: string,
	coins: number,
	uid: Uid, -- bébé reçu ("" : pièces seulement)
	species: SpeciesId,
	short: boolean, -- cadeau compté directement, sans capsule (message seulement)
}
export type CelebrateMegaResult = { success: boolean, points: number, babies: number, coins: number }
export type CelebrateDrop = { uid: Uid, species: SpeciesId, mutation: MutationId } -- lunarDrop, luckyDrop
export type CelebrateDexNew = { species: SpeciesId, mutation: MutationId, star: number }
export type CelebrateObjectiveDone = { slot: number, id: number }
export type CelebrateDay = { day: number } -- objectivesCard, newObjectives
export type CelebratePlopDay = { day: number, reward: string }
export type CelebrateOnboarding = { step: number, hint: string }
export type CelebrateSleepy = { minutes: number }
export type CelebrateUnlock = { kind: string, id: string }
export type CelebrateSaddle = { saddle: number }
export type CelebratePurchase = { key: string }
export type CelebrateClapCount = { n: number }
export type CelebrateFanfare = { threshold: number }
export type CelebratePhoto = { on: boolean }

-- =================================================================================================
-- Contrat v2.0 (GDD v2.0, docs/04 §27) : charges utiles figées des paquets du jeu complet. Les deux
-- voies (serveur, interface) se parlent par ces types ; aucun n'est envoyé tant que son interrupteur
-- Config/Features est coupé.
-- =================================================================================================

-- Sortes de prestige (Logic/Prestige.apply) : Grand Splorch (nouveau Record R ou non), Petit Splorch
-- (r après la renaissance ≤ Record R, hors file), Jelly Ascend
export type PrestigeKind = "splorch" | "petit" | "ascend"
export type UpgradeCurrency = "coins" | "confetti"

-- Instantané VERSIONNÉ de l'écran Améliorations (règle 6 du GDD §10.8) : seule source de l'écran et
-- de la puce « Prochain achat ». version croît à chaque mutation d'une valeur lue (achat, règlement,
-- prestige, gain de Confettis) ; le client ignore un instantané plus ancien que celui affiché.
-- levels[id] = niveau de chaque famille (Config/Upgrades.Families.id), de chaque ligne de l'Atelier
-- (WorkshopRows.id) et de chaque ligne de Fun ("fun.<id>" : objets achetés) ; caps[id] = niveau
-- maximal achetable MAINTENANT (ouverture, plafond de la boucle, interrupteur ; 0 = fermé)
export type UpgradeSnapshot = {
	coins: number,
	confetti: number,
	levels: { [string]: number },
	caps: { [string]: number },
	r: number,
	bestR: number,
	ascend: number,
	version: number,
}

-- Réponse à BuyUpgrade (et à BuyTile, même chemin) : TOUJOURS envoyée, refus « périmé » compris
-- (lot A2, docs/04 §27.12 A2-10) : le refus périmé est muet DEDANS (reason = nil, from = to = niveau du
-- serveur, spent = 0, instantané à jour ; le client le reconnaît à from == to sans raison).
-- from / to = niveaux avant / après (to == from sur un refus) ; spent = somme exacte débitée
-- (UpgradeMath.bulk) ; reason = clé de texte du refus (nil si acheté ou périmé) ; snapshot = état après
export type UpgradeResultPayload = {
	id: string,
	from: number,
	to: number,
	spent: number,
	currency: UpgradeCurrency,
	reason: string?,
	snapshot: UpgradeSnapshot,
}

-- Pression d'une Plopette (HelperPress, non fiable, regroupée par tick) : le serveur choisit la cible
-- et l'heure tPress (Clock.now() du serveur) ; il revérifie à tPress, l'issue arrive par DataPatch
export type HelperPressEntry = { helper: number, uid: Uid, tPress: number }
export type HelperPressPayload = { ownerId: number, presses: { HelperPressEntry } }
export type HelperState = "idle" | "moving" | "nap" | "paused"

-- Charges des célébrations v2.0 (sortes dans CelebrateKind, fusionnées au lot I)
export type CelebratePetitSplorch = { userId: number, level: number, startedAt: number, endsAt: number }
export type CelebrateAscend = {
	userId: number,
	ascend: number, -- A après l'Ascension
	startR: number, -- Grand Splorch de départ
	bestR: number,
	startedAt: number,
	burstAt: number, -- Prestige.apply à burstAt (Balance.Ascend.BurstAt)
	endsAt: number,
	flyer: { s: SpeciesId, m: MutationId, st: number, z: number }, -- taille copiée au début
}
export type CelebrateTier = { family: string, tier: number, key: string }
export type CelebrateUnlock2 = { recordR: number, keys: { string } } -- déblocages du §4.29
export type CelebrateConfetti = { n: number, source: string }
export type CelebrateTrackTier = { tier: number, reward: string }
export type CelebrateCarnet = { tier: number, reward: string }
export type CelebrateMastery = { species: SpeciesId }
export type CelebrateRegainDone = { bestR: number, confetti: number }
export type CelebrateRecordStep = { share: number } -- 0,25 / 0,5 / 0,75
export type CelebrateWelcomeV2 = { highlights: { string } } -- 3 plus beaux déblocages déjà gagnés

-- Attributs répliqués du ranch ajoutés par la v2.0 (RanchService, sur le dossier du ranch) :
-- BestR, Ascend, SplorchReady, AscendReady, PetitSplorchAt, Monuments, DecoPerso, HaloOn,
-- TapisTier, GloveTier, ApronTier (docs/04 §27.5) ; lot A4 : HelperMode et Helpers (Plopettes,
-- HelperService), GiantTier (jalons géants, QuestService), DecorGold et GoldPennants (RanchService),
-- Palette et Cushions (CommunityService). Chacun ABSENT tant que son interrupteur est coupé ou que
-- le profil est v1. L'habillage reste le thème public de la v1.3 (cosmetics.theme : 14 valeurs en
-- v2.0, décision C2)
export type RanchAttributesV2 = {
	BestR: number,
	Ascend: number,
	SplorchReady: boolean,
	AscendReady: boolean,
	PetitSplorchAt: number,
	Monuments: number,
	DecoPerso: string, -- 12 identifiants séparés par des virgules (0 = vide)
	HaloOn: boolean,
	TapisTier: number,
	GloveTier: number,
	ApronTier: number,
	-- Plopettes [Helpers] : "active" | "nap" | "paused" (sieste, pause pendant un prestige), posé au
	-- changement seulement ; nombre de Plopettes du ranch (0 à 6)
	HelperMode: string,
	Helpers: number,
	GiantTier: number, -- [Mastery] jalons géants atteints (0 à 4 : 1e15, 1e18, 1e21, 1e24 ; Squishy-Soleil ≥ 3)
	DecorGold: number, -- [RanchTiers] décorations dorées : bit k − 1 quand decorBuilds[k] ≥ 10 (18 bits)
	GoldPennants: boolean, -- [Workshop] « Fanions dorés » de « Pour le plaisir » achetés
	KeptDecor: number, -- [Workshop, profil v2] décorations gardées au prestige (0 à 12 ; lot I, D15)
	Palette: string, -- palette choisie du spectacle du Grand Splorch ("" = celle du ranch ; CommunityService)
	Cushions: string, -- coussins choisis des enclos ("" = ceux du ranch ; CommunityService)
}

-- Défi de la semaine (profil : weeklyTrack.challenges, 3 par période)
export type ChallengeEntry = { id: number, p: number, done: boolean }

return {}
