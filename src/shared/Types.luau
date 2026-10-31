--!strict
-- Types partagés du contrat (docs/04-architecture.md). Aucun code exécutable : ce module ne
-- renvoie qu'une table vide ; on l'importe pour ses `export type`.
--   local Types = require(Shared.Types)
--   local function f(rec: Types.NebbyRecord) … end
-- Registre partagé : ajouts ciblés autorisés (jamais de suppression ni de renommage).

-- =============================================================================================
-- Nebbies et collection
-- =============================================================================================

export type NebbyCode = number -- s | (f << 6) | (v << 9) (Config/Nebbies.pack)
export type RarityId = number -- 1 Commun … 7 Cosmique
export type FormId = number -- 0 Normale, 1 Aurora, 2 Frozen, 3 Blazing, 4 Eclipse, 5 Prismatic
export type VariantBits = number -- 1 Golden, 2 Huge, 4 Starborn
export type Uid = string -- "u<n>" (≤ 12 caractères)

-- Un Nebby de la collection (profile.nebbies[uid])
export type NebbyRecord = {
	s: number, -- espèce 1-36
	f: number, -- forme 0-5
	v: number, -- variantes (bits)
	st: number, -- étoiles 1-5
	lk: boolean?, -- verrou
}

export type UpgradeTrack = "conga" | "stride" | "lure" | "perches" | "guard"
export type ZoneKey = "meadow" | "glade" | "crater"
export type WeatherKey = "aurora" | "frost" | "solar" | "meteor" | "rainbow" | "eclipse"
export type InputKind = number -- 1 tactile, 2 clavier-souris, 3 manette
export type Lang = "auto" | "en" | "fr"

-- =============================================================================================
-- Profil sauvegardé (Data/Schema v1, GDD §12.6)
-- =============================================================================================

export type ProfileSettings = {
	zen: boolean,
	reducedMotion: boolean,
	lowGraphics: boolean,
	music: boolean,
	sfx: boolean,
	autoCrew: boolean,
	refuseInvites: boolean,
	lang: string,
}

export type QuestSlot = { id: number, p: number, done: boolean, claimed: boolean }

export type Profile = {
	version: number,
	glow: number,
	glowCarry: number,
	lastSettle: number,
	lastOnline: number,
	idleRate: number,
	stardust: number,
	supernovas: number,
	upgrades: { conga: number, stride: number, lure: number, perches: number, guard: number },
	boosts: { personalUntil: number },
	caps: { day: number, snipDust: number, wispDust: number, cheers: number, duo: boolean },
	nebbies: { [Uid]: NebbyRecord },
	nextUid: number,
	perchIncome: number,
	atlas: { number },
	badges: { number },
	atlasRewards: number,
	onboarding: { step: number, p: number },
	daily: { day: number, step: number },
	quests: { day: number, list: { QuestSlot }, rerolls: number, starClaimed: boolean },
	weekly: { week: number, banked: number, claimed: boolean },
	rookie: { sessions: number, playSeconds: number, done: boolean },
	settings: ProfileSettings,
	cosmetics: { style: string, title: string, nestTheme: string },
	unlocks: { styles: { [string]: boolean }, titles: { [string]: boolean }, themes: { [string]: boolean } },
	weeklyBest: { week: number, conga: number },
	starterKit: boolean,
	stats: { [string]: number },
	passes: { [string]: boolean },
	receipts: { string },
	codes: { [string]: boolean },
	flags: { strikes: number, lbBanned: boolean },
}

-- =============================================================================================
-- État serveur du monde (jamais envoyé tel quel)
-- =============================================================================================

-- Nœud d'une file (CongaService)
export type LineNode = {
	code: NebbyCode,
	at: number, -- Clock.now() de la capture
}

-- Nebby sauvage ou libre (SpawnService)
export type WildNebby = {
	id: number, -- 1-65535 (réutilisé)
	code: NebbyCode,
	zone: string?, -- nil pour un Nebby libre ou personnel hors zone
	anchor: Vector3, -- ancre (Y = sol)
	seed: number, -- graine de flânerie (SeededPath.wander)
	t0: number, -- Clock.now() d'apparition
	expiresAt: number,
	dizzyUntil: number, -- étourdi (personne ne peut l'attraper sauf prioritySlot)
	prioritySlot: number, -- 0 = aucune priorité
	onlyFor: number, -- UserId (0 = tout le monde)
	group: string?, -- ex. "burst:<id>" (plafond par joueur)
	groupCap: number?,
	loose: boolean,
	from: Vector3?, -- point de départ de l'arc de dispersion
}

-- Vue d'un joueur pendant un tick (construite par CongaService, passée aux hooks)
export type Actor = {
	player: Player,
	userId: number,
	slot: number, -- 1-12 (0 = pas de Nid)
	-- position serveur de la HumanoidRootPart ; sur un tick refusé (valid = false), pos = prev =
	-- dernière position VALIDÉE (jamais la position brute, qui peut être un téléport)
	pos: Vector3,
	-- dernière position validée avant ce tick : prev → pos est un déplacement validé (balayages)
	prev: Vector3,
	valid: boolean, -- MoveCheck a validé ce tick (sinon : ni capture, ni coupe, ni parade, ni vol)
	zen: boolean,
	crewId: number, -- 0 = aucun
	rookie: boolean,
	touch: boolean, -- entrée tactile déclarée (aide +0,3)
}

-- Modificateurs d'apparition poussés par EventService vers SpawnService
export type SpawnModifiers = {
	form: number?, -- forme météo (probabilité formChance = Balance.Spawn.WeatherFormChance)
	formChance: number,
	intervalDiv: number, -- intervalles ÷ (météo Meteor ×3, Frenzy ×4 ; produit)
	capMult: number, -- plafonds × (Meteor ×1,5, Frenzy ×2 ; produit)
	featured: number?, -- espèce vedette (Starfall)
	featuredChance: number,
	starbornChance: number,
}

-- =============================================================================================
-- Informations portées par les signaux serveur (src/server/Signals.luau)
-- =============================================================================================

export type CatchInfo = {
	code: NebbyCode,
	rarity: number,
	zone: string?, -- zone de l'ancre du Nebby
	loose: boolean, -- Nebby libre (coupe, explosion)
	recovered: boolean, -- reprise de ses propres Nebbies (priorité)
	personal: boolean,
	n: number, -- longueur de la file après capture
}

export type ParadeInfo = {
	count: number,
	codes: { NebbyCode },
	uids: { Uid }, -- uids créés dans la collection
	glow: number, -- Glow crédité
	bonus: number, -- Conga Bonus appliqué
	atBeacon: boolean,
	idleSeconds: number, -- glow / revenu passif (0 si revenu nul)
	newEntries: number, -- nouvelles entrées d'Atlas
	forced: boolean, -- encaissement forcé avant Supernova
}

export type SnipInfo = {
	snipper: Player?, -- nil si Gloomwisp
	victim: Player,
	count: number, -- Nebbies détachés
	byWisp: boolean,
	rewarded: boolean, -- Stardust accordée au coupeur
	dust: number,
}

export type CometSignal = {
	kind: "warn" | "impact" | "pickup" | "steal" | "drop" | "bank" | "burst",
	id: number,
	player: Player?, -- porteur / encaisseur
	from: Player?, -- volé à
}

-- =============================================================================================
-- Réseau : charges utiles des remotes serveur → client (GDD §12.5)
-- =============================================================================================

-- WildEvent / WorldSnapshot / LineEvent(clear) / SnipEvent : une apparition
export type WildSpawn = {
	id: number,
	code: NebbyCode,
	x: number, -- ancre XZ (Y = WorldLayout.groundY)
	z: number,
	seed: number,
	t0: number,
	life: number, -- s depuis t0
	dizzyUntil: number?, -- Nebby libre étourdi jusqu'à (Clock)
	prioritySlot: number?, -- slot prioritaire (victime)
	fromX: number?, -- départ de l'arc de dispersion
	fromZ: number?,
	personal: boolean?, -- envoyé à ce seul client
}

export type WildDespawn = {
	id: number,
	reason: "expired" | "caught" | "cleared",
	slot: number?, -- capteur (reason = caught)
}

export type WildEventPayload = { spawns: { WildSpawn }, despawns: { WildDespawn } }

-- LineEvent : liste d'opérations, appliquées dans l'ordre de `ver` (par slot)
export type LineAddOp = {
	op: "add",
	slot: number,
	ver: number,
	codes: { NebbyCode }, -- ajoutés en queue, dans l'ordre
	ids: { number }, -- ids des sauvages capturés (même ordre ; 0 si inconnu)
}

export type LineBankOp = {
	op: "bank",
	slot: number,
	ver: number,
	count: number,
	glow: number,
	bonus: number,
	atBeacon: boolean,
	newEntries: number,
}

export type LineClearOp = {
	op: "clear",
	slot: number,
	ver: number,
	reason: "death" | "leave" | "reset" | "supernova",
	loose: { WildSpawn }, -- Nebbies libérés (vide si reset)
}

export type LineOwnerOp = {
	op: "owner",
	slot: number,
	ver: number, -- 0 : nouvelle vie de la file
	userId: number, -- 0 = Nid libre
}

export type LineOp = LineAddOp | LineBankOp | LineClearOp | LineOwnerOp

-- SnipEvent : une coupe (modifie la file : partage la séquence `ver` de LineEvent)
export type SnipEventPayload = {
	snipperSlot: number, -- 0 si Gloomwisp
	victimSlot: number,
	ver: number, -- version de la file de la victime APRÈS la coupe
	cutIndex: number, -- premier nœud détaché (les nœuds cutIndex … n partent)
	count: number,
	looseIds: { number },
	loose: { WildSpawn }, -- apparitions des Nebbies libres (même ordre que looseIds)
	byWisp: boolean,
	wispId: number?,
	x: number, -- point touché
	y: number,
	z: number,
	dust: number, -- Stardust gagnée par le coupeur (0 si plafond, bouclier, Gloomwisp)
}

-- PathStream / PathSnapshot / WorldSnapshot.paths : runs décodés (Logic/PathCodec)
export type PathEntry = {
	slot: number,
	firstSeq: number,
	points: { Vector3 },
}

-- EventState (§12.5) : état complet, renvoyé à chaque changement
export type WeatherState = {
	key: string,
	form: number?,
	startsAt: number,
	endsAt: number,
	forced: boolean?, -- LiveOps
}

export type CometState = {
	id: number,
	phase: "warn" | "ground" | "carried" | "banked" | "burst",
	x: number, -- point d'impact / position au sol
	z: number,
	code: NebbyCode,
	warnAt: number,
	impactAt: number,
	burstAt: number,
	carrierId: number?, -- UserId du porteur
	carrierSince: number?,
	prevCarrierId: number?,
	endedAt: number?, -- banked / burst
}

export type BeaconState = {
	phase: "warn" | "active" | "success" | "fail",
	warnAt: number,
	startsAt: number,
	endsAt: number,
	points: number,
	goal: number,
	topUserId: number?,
}

export type BoostState = {
	endsAt: number,
	source: "goldenNight" | "glowParty" | "starfall" | "liveOps",
	buyerId: number?,
}

export type StarfallState = { startsAt: number, endsAt: number, featured: number }

export type WispState = {
	id: number,
	seed: number,
	t0: number, -- SeededPath.chordAt(seed, t0, t)
	poppedAt: number?,
	poppedBy: number?, -- UserId
	respawnAt: number?,
}

export type EventStatePayload = {
	t: number, -- Clock.now() à l'émission
	weather: WeatherState?,
	comet: CometState?,
	beacon: BeaconState?,
	frenzy: { endsAt: number }?,
	serverBoost: BoostState?,
	starfall: StarfallState?,
	wisps: { WispState },
	snipsDisabled: boolean,
	activePlayers: number,
}

-- Banner (§6.5)
export type BannerKind =
	"mythicCatch"
	| "legendaryCatch"
	| "cometWarn"
	| "cometPickup"
	| "cometStolen"
	| "cometBanked"
	| "cometBurst"
	| "supernova"
	| "megaParade"
	| "serverRecord"
	| "glowParty"
	| "weather"
	| "beaconStart"
	| "beaconWin"
	| "beaconTop"
	| "beaconFail"
	| "goldenNight"
	| "starfall"
	| "rookieEnd"
	| "atlasMilestone"
	| "liveOps"

export type BannerPayload = {
	kind: BannerKind,
	args: { [string]: any }, -- name, userId, code, level, n, key, minutes…
	priority: number, -- 1 = plus haute
	personal: boolean?, -- envoyé à un seul joueur
}

-- Feedback (§12.5) : refus et confirmations pour un joueur
export type FeedbackTone = "info" | "success" | "warning" | "error" | "reward"
export type FeedbackPayload = {
	key: string, -- clé de localisation "feedback.*"
	vars: { [string]: any },
	tone: FeedbackTone,
}

-- Celebrate (§12.5) : moments personnels
export type CelebrateKind =
	"supernova"
	| "atlasNew"
	| "atlasMilestone"
	| "speciesComplete"
	| "questDone"
	| "questClaimed"
	| "dailyClaimed"
	| "starforge"
	| "upgrade"
	| "offline"
	| "purchase"
	| "cometBanked"
	| "rookieEnd"
	| "release"
	| "unlock"

export type CelebratePayload = {
	kind: CelebrateKind,
	data: { [string]: any },
}

export type CrewEntry = { id: number, userIds: { number } }
export type CrewStatePayload = { crews: { CrewEntry } }
export type CrewInvitePayload = { inviterId: number, expiresAt: number }
export type CheerPromptPayload = { heroId: number, level: number, expiresAt: number }
export type PingPayload = { userId: number, kind: number }

export type LineSnapshot = {
	slot: number,
	userId: number,
	ver: number,
	codes: { NebbyCode },
}

export type WorldSnapshotPayload = {
	serverTime: number,
	tick: number,
	lines: { LineSnapshot },
	paths: buffer, -- format PathStream (plusieurs runs par slot possibles)
	wild: { WildSpawn },
	events: EventStatePayload,
	crews: CrewStatePayload,
}

-- Aperçu de Supernova (EconomyService.supernovaPreview, affiché par Panels/Supernova)
export type SupernovaPreview = {
	level: number, -- R actuel
	cost: number,
	glow: number,
	canAfford: boolean,
	inHarbor: boolean,
	incomeNow: number, -- bonus de revenu actuel (+0,40 × R)
	incomeNext: number,
	congaCapNow: number, -- niveaux Conga max
	congaCapNext: number,
	dashNow: number, -- recharge du Dash
	dashNext: number,
	auraNext: string?, -- aura débloquée par la prochaine Supernova
	resets: { string }, -- "glow", "conga", "stride", "lure"
	keeps: { string }, -- "nebbies", "perches", "guard", "stardust", "atlas", "cosmetics", "quests", "stats"
}

-- =============================================================================================
-- Client
-- =============================================================================================

export type PanelName =
	"Upgrades"
	| "Supernova"
	| "Collection"
	| "Goals"
	| "Shop"
	| "Crew"
	| "Settings"
	| "ReturnScreen"

export type HudElement =
	"glow"
	| "stardust"
	| "line"
	| "dash"
	| "ping"
	| "rail"
	| "rail.Upgrades"
	| "rail.Collection"
	| "rail.Goals"
	| "rail.Shop"
	| "eventPill"
	| "minimap"
	| "status"
	| "questTracker"
	| "crew"
	| "settings"

-- Miroir client d'une file (WorldStateController)
export type LineMirror = {
	slot: number,
	userId: number,
	ver: number,
	codes: { NebbyCode },
}

-- Miroir client d'un sauvage (WorldStateController)
export type WildMirror = {
	id: number,
	code: NebbyCode,
	anchor: Vector3,
	seed: number,
	t0: number,
	expiresAt: number,
	dizzyUntil: number,
	prioritySlot: number,
	from: Vector3?,
	personal: boolean,
}

return {}
