--!strict
-- Déclaration de TOUS les remotes du jeu : nom → type ("event" | "unreliable" | "func").
-- Net.setup() les crée côté serveur ; Net.event("Nom") les récupère partout (une faute de frappe
-- dans un nom lève une erreur claire). Registre partagé : ajouts ciblés autorisés (une ligne par
-- remote, son type, sa charge utile et son propriétaire en commentaire ; jamais de renommage).
-- Règle : un remote client → serveur porte une INTENTION, jamais une valeur de jeu ; le serveur
-- valide chaque argument (Shared/Util/Validate) et limite le débit (Server/Util/RateLimit). Débit et
-- forme de chaque intention : Shared/Config/Intents.luau (source unique, lue par le fuzzeur).
-- Aucun RemoteFunction (aucun client ne peut bloquer le serveur, aucun serveur n'attend un client).
-- Charges utiles détaillées : Shared/Types.luau et docs/04 §10.

return {
	-- =========================================================================================
	-- Socle
	-- =========================================================================================
	-- Données joueur (DataService ↔ StateController)
	DataSnapshot = "event", -- serveur → client : état complet (clés privées retirées)
	DataPatch = "event", -- serveur → client : (patch, removedKeys, entries?: Types.DataPatchEntries)
	RequestSnapshot = "event", -- client → serveur : () redemande l'état complet (2 / 10 s)

	-- Retours au joueur (Server/Util/Notify)
	Feedback = "event", -- serveur → client : (Types.FeedbackPayload)
	Celebrate = "event", -- serveur → client : (Types.CelebratePayload)
	Banner = "event", -- serveur → client : (Types.BannerPayload)

	-- =========================================================================================
	-- Client → serveur : intentions (Config/Intents : propriétaire, débit, arguments)
	-- =========================================================================================
	Press = "event", -- (uid, tClient) SquishyService
	PickUp = "event", -- (uid) SquishyService
	PutDown = "event", -- () SquishyService
	Throw = "event", -- () SquishyService
	FuseMenu = "event", -- (uidA, uidB) SquishyService
	FuseAll = "event", -- () SquishyService
	BuyTile = "event", -- (tile) EconomyService
	MoveSquishy = "event", -- (uid, to) SquishyService
	ClaimMail = "event", -- (uid) SquishyService
	Sell = "event", -- (uids, confirmed) SquishyService
	Release = "event", -- (uids, confirmed) SquishyService
	SetLock = "event", -- (uid, locked) SquishyService
	SetBestFriend = "event", -- (uid, slot) SquishyService
	SetMount = "event", -- (uid) SquishyService
	Ride = "event", -- (on) SquishyService
	EquipOutfit = "event", -- (outfit, uid?) SquishyService
	Leap = "event", -- (dirX, dirZ, tClient) ChaseService
	Catch = "event", -- (id, tClient) ChaseService (capture vérifiée à son instant tClient)
	BoopHold = "event", -- (ownerId, uid, holding) RushService
	SetMode = "event", -- (rush) RushService
	RefuseBooper = "event", -- (userId) RushService
	MegaPress = "event", -- (tClient) EventService
	AdminCommand = "event", -- (command, arg) EventService (administrateurs seulement, Data/Admins)
	GrandSplorch = "event", -- (film, flyer) SplorchService
	FeedPlop = "event", -- (holding) QuestService
	ClaimObjective = "event", -- (slot) QuestService
	RerollObjective = "event", -- (slot) QuestService
	ClaimDexReward = "event", -- () QuestService
	UiSeen = "event", -- (screen) QuestService → Signals.UiSeen (RushService : carte du choix affichée)
	-- () QuestService (v2.0, lot A4, N23) : navigation dans un menu ; réveille les Plopettes seulement
	MenuActivity = "event",
	PetPress = "event", -- (ownerId, uid, tClient) CommunityService
	SetSetting = "event", -- (key, value) CommunityService
	EquipCosmetic = "event", -- (kind, id) CommunityService
	Emote = "event", -- (kind) CommunityService
	Clap = "event", -- (heroId) CommunityService
	ReportBlocked = "event", -- (userIds) CommunityService
	RequestWorld = "event", -- () RanchService → Signals.WorldRequested (EventService, ChaseService)
	SetInputType = "event", -- (kind, tenFoot) DiagnosticsService (analytique seulement)
	ReportError = "event", -- (kind, key, message, trace, ctx) DiagnosticsService
	RequestDiagnostics = "event", -- (tab) DiagnosticsService (administrateurs seulement)
	ClientEvent = "event", -- (kind) DiagnosticsService : analytique seulement (qualityReduced, shopOpened)

	-- =========================================================================================
	-- Serveur → client
	-- =========================================================================================
	RanchSnapshot = "event", -- (Types.RanchSnapshotPayload) RanchService : arrivée, RequestWorld
	RanchPatch = "event", -- (Types.RanchPatchPayload) RanchService : groupé par tick, numéroté
	Fence = "event", -- (Types.FencePayload) RanchService : tous (Rush, pet-sitting)
	ChaseEvent = "event", -- (Types.ChaseEventPayload) ChaseService : tous, ou un seul (personnelles)
	EventState = "event", -- (Types.EventStatePayload) EventService : tous, à chaque changement
	MegaBeat = "unreliable", -- (Types.MegaBeatPayload) EventService : tous, 4 Hz pendant le MEGA
	BoopState = "event", -- (Types.BoopStatePayload) RushService : tous
	ModePrompt = "event", -- () RushService : le joueur (carte du choix Rush / Cozy, au calme)
	HoldState = "event", -- (Types.HoldStatePayload) QuestService (bol) et RanchService (dalle) : le joueur
	EmoteShow = "event", -- (Types.EmoteShowPayload) CommunityService : tous
	ClapPrompt = "event", -- (Types.ClapPromptPayload) CommunityService : spectateurs du spectacle complet
	LeaderboardState = "event", -- (Types.LeaderboardPayload) LeaderboardService : le joueur
	DiagnosticsSnapshot = "event", -- (Types.DiagnosticsSnapshot) DiagnosticsService : l'administrateur demandeur

	-- =========================================================================================
	-- Contrat v2.0 (GDD v2.0 §12.7, docs/04 §27.5) : déclarés et créés par Net.setup, écoutés
	-- seulement quand leur paquet est fait (interrupteurs Config/Features coupés jusque-là).
	-- Intentions : forme, débit et propriétaire dans Config/IntentsV2 (déplacées vers Config/Intents
	-- par le paquet qui branche le handler).
	-- =========================================================================================
	BuyUpgrade = "event", -- (id, mode, expectedLevel) EconomyService
	JellyAscend = "event", -- (confirm) SplorchService
	PlaceDeco = "event", -- (item, slot) CommunityService
	GiveHeart = "event", -- (ownerId) CommunityService
	SetPhotoMode = "event", -- (on) CommunityService
	-- Serveur → client
	UpgradeResult = "event", -- (Types.UpgradeResultPayload) EconomyService : le joueur, à chaque réponse
	HelperPress = "unreliable", -- (Types.HelperPressPayload) HelperService : groupé par tick, le joueur et
	-- les clients qui dessinent ce ranch en détail complet (l'issue arrive par DataPatch)
} :: { [string]: string }
