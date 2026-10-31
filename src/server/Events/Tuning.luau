--!strict
-- Réglages techniques du paquet « events » qui n'ont pas (encore) de place dans Shared/Config.
-- Chaque valeur est nommée et sourcée ; les nombres de gameplay restent dans Config/Balance,
-- Config/Events et Config/Quests (docs/04-architecture.md §1, règle 5).

local Tuning = {
	-- Bannières de serveur (GDD §6.5, docs §10.3) : file de 3, une diffusion toutes les 3 s,
	-- une même source au plus une bannière toutes les 10 s
	BannerQueueMax = 3,
	BannerInterval = 3,
	BannerSourceCooldown = 10,

	-- EventState : durée pendant laquelle un résultat (Comète encaissée ou éclatée, Balise
	-- échouée) reste dans l'état envoyé aux clients, le temps de jouer l'effet (s)
	ResultLinger = 5,

	-- Gloomwisps : hauteur du « corps » au-dessus du sol (≈ HumanoidRootPart) pour le test
	-- |Δy| des coupes de CongaService (studs)
	WispBodyHeight = 3,

	-- Services lents (step) : période de travail et écart maximal compté si le serveur a gelé (s)
	SlowStepInterval = 1,
	MaxStepGap = 5,

	-- QuestService : écriture des temps de jeu dans le profil (limite les patchs répliqués) (s)
	PlayFlushInterval = 10,
	-- Accueil (GDD §3, §7.4) : apparitions dirigées jusqu'à la fin de cette quête ; Rare garanti
	-- (une fois par compte) au début de celle-ci (ids de Config/Quests.Onboarding)
	DirectedUntilQuest = "q3",
	GuaranteedRareQuest = "q4",

	-- LiveOps : longueur maximale d'une commande, âge maximal d'un message reçu (s)
	LiveOpsCommandMax = 32,
	LiveOpsMaxAge = 60,

	-- Codes promo (docs §10.1) : longueur maximale
	CodeMaxLength = 20,

	-- Classements : nouvelles tentatives DataStore (backoff 1, 2, 4… × délai) et cache des noms
	DataStoreAttempts = 3,
	DataStoreRetryDelay = 1,
	NameCacheMax = 256,
	-- Fermeture du serveur : attente maximale d'un vidage en cours avant d'écrire le reste de la
	-- file (BindToClose laisse 30 s en tout, partagées avec les sauvegardes des profils) (s)
	CloseFlushTimeout = 10,
}

return Tuning
