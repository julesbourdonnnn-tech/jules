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
	emoteLeft: string, -- "bravo" | "bellyFlop" | "crown"
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

-- Celebrate : moments personnels (Server/Util/Notify.celebrate). Sortes : CelebrateKinds ci-dessous.
export type CelebrateKind = string
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
	best: { s: SpeciesId, m: MutationId, z: number, zg: number }?, -- silhouette au-dessus du ranch
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

-- Clôture (Rush ou pet-sitting) : squishies du ranch `slot` posés à la clôture côté rue
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

export type SpectacleEntry = {
	kind: "splorch" | "dance",
	userId: number, -- héros (0 pour la danse)
	startAt: number, -- Clock.now() prévu
}

export type SpectacleCurrent = {
	kind: "splorch" | "dance",
	userId: number,
	startedAt: number,
	burstAt: number, -- Grand Splorch : application au profil (startedAt + Balance.Splorch.BurstAt)
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
	gauge: { points: number, target: number, partyUntil: number },
	boost: { kind: "" | "wobble" | "squish" | "admin", untilT: number, byName: string },
	spectacle: { current: SpectacleCurrent?, queue: { SpectacleEntry } },
	features: EventFeatures,
	offset: number, -- Clock.setOffset du serveur (commandes de développement) : le client l'applique
}

export type MegaBeatPayload = { points: number, target: number, presses: number, t: number }

export type BoopStatePayload = {
	booperId: number,
	ownerId: number,
	uid: Uid,
	endsAt: number, -- Clock.now() de fin prévue (2,5 s ou 5 s, peut changer en cours)
	state: "hold" | "done" | "cancel",
}

export type HoldStatePayload = { kind: "feed", endsAt: number, active: boolean }

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
	recentBuy: boolean, -- 2e confirmation (paquet acheté il y a < 30 min, ≥ moitié restante)
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
}

return {}
