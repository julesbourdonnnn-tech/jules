--!strict
-- Déclaration de TOUS les remotes du jeu : nom → type ("event" | "unreliable" | "func").
-- Net.setup() les crée côté serveur ; Net.event("Nom") les récupère partout.
-- Charges utiles, validation, débit et propriétaires : docs/04-architecture.md §10.
-- Registre partagé : ajouts ciblés autorisés (une ligne par remote, jamais de renommage).

return {
	-- Données joueur (DataService ↔ StateController)
	DataSnapshot = "event", -- serveur → client : état complet
	DataPatch = "event", -- serveur → client : (patch, removedKeys)
	RequestSnapshot = "event", -- client → serveur : redemande l'état complet

	-- Client → serveur : intentions (GDD §12.5)
	Dash = "event", -- () — CongaService
	BuyUpgrade = "event", -- (track: string) — EconomyService
	Supernova = "event", -- () — EconomyService
	Fuse = "event", -- (uid: string) — AtlasService
	FuseAll = "event", -- () — AtlasService
	Release = "event", -- (uids: {string}) — AtlasService
	SetLock = "event", -- (uid: string, locked: boolean) — AtlasService
	ClaimDaily = "event", -- () — QuestService
	ClaimQuest = "event", -- (kind: string, slot: number) — QuestService
	RerollQuest = "event", -- (slot: number) — QuestService
	CrewInvite = "event", -- (userId: number) — CrewService
	CrewRespond = "event", -- (inviterId: number, accept: boolean) — CrewService
	CrewLeave = "event", -- () — CrewService
	Ping = "event", -- (kind: number) — CrewService
	Cheer = "event", -- (heroId: number) — CrewService
	SetSetting = "event", -- (key: string, value: boolean | string) — NestService
	SetInputType = "event", -- (kind: number) — CongaService
	EquipCosmetic = "event", -- (kind: string, id: string) — NestService
	RequestWorld = "event", -- () — CongaService
	RequestPath = "event", -- (slot: number) — CongaService
	AdminCommand = "event", -- (command: string) — EventService (Data/Admins seulement)
	RedeemCode = "func", -- (code: string) → status: string — QuestService

	-- Serveur → client
	PathStream = "unreliable", -- (buf: buffer) 10 Hz — CongaService
	PathSnapshot = "event", -- (slot: number, buf: buffer) — CongaService
	WorldSnapshot = "event", -- (WorldSnapshotPayload) — CongaService
	LineEvent = "event", -- ({LineOp}) — CongaService
	WildEvent = "event", -- (WildEventPayload) 4 Hz — SpawnService
	SnipEvent = "event", -- (SnipEventPayload) — CongaService
	EventState = "event", -- (EventStatePayload) — EventService
	Banner = "event", -- (BannerPayload) — CrewService (file d'attente serveur)
	Feedback = "event", -- (FeedbackPayload) — tous (via Server/Util/Notify)
	Celebrate = "event", -- (CelebratePayload) — tous (via Server/Util/Notify)
	CrewState = "event", -- (CrewStatePayload) — CrewService
	CrewInvitePrompt = "event", -- (CrewInvitePayload) — CrewService
	CheerPrompt = "event", -- (CheerPromptPayload) — CrewService
	PingShow = "event", -- (PingPayload) — CrewService
} :: { [string]: string }
