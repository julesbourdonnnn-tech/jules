--!strict
-- Bus de signaux internes du serveur (contrat, docs/04-architecture.md §7).
-- Les services communiquent « vers le haut » de l'ordre d'initialisation par ces signaux :
-- un service peut émettre ou écouter n'importe lequel, quel que soit son rang, alors qu'un appel
-- direct d'API n'est permis que vers un service initialisé AVANT lui.
-- Chaque signal a UN émetteur (colonne « émis par ») ; les abonnés se branchent dans Start().
-- Les handlers s'exécutent chacun dans leur propre thread (Shared/Util/Signal) : jamais de yield
-- long dans un handler qui mute un profil sans revérifier DataService.get(player).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)

local Signals = {
	-- NestService : profil chargé, Nid attribué, personnage placé (entonnoir étape 1)
	PlayerReady = Signal.new() :: Signal.Signal<Player, number>, -- (player, slot)
	-- NestService / CongaService : déplacement imposé par le serveur (PivotTo) → exemption MoveCheck
	ServerMoved = Signal.new() :: Signal.Signal<Player>,

	-- CongaService
	Caught = Signal.new() :: Signal.Signal<Player, Types.CatchInfo>,
	LineChanged = Signal.new() :: Signal.Signal<Player, number>, -- (player, n) au plus 1 fois par tick
	Parade = Signal.new() :: Signal.Signal<Player, Types.ParadeInfo>,
	Snipped = Signal.new() :: Signal.Signal<Types.SnipInfo>,
	Dashed = Signal.new() :: Signal.Signal<Player>,
	EscortTime = Signal.new() :: Signal.Signal<Player, number>, -- (escorteur, secondes) par seconde pleine
	MoveViolation = Signal.new() :: Signal.Signal<Player, number>, -- (player, infractions de la session)

	-- EconomyService
	UpgradeBought = Signal.new() :: Signal.Signal<Player, Types.UpgradeTrack, number>, -- (player, piste, nouveau niveau)
	Supernova = Signal.new() :: Signal.Signal<Player, number>, -- (player, nouveau R)
	IdleSettled = Signal.new() :: Signal.Signal<Player, number, number>, -- (player, glow crédité, secondes)
	RateChanged = Signal.new() :: Signal.Signal<Player, number>, -- (player, nouvel idleRate)

	-- AtlasService
	PerchesChanged = Signal.new() :: Signal.Signal<Player, number>, -- (player, nombre de perchoirs)
	AtlasEntry = Signal.new() :: Signal.Signal<Player, number, number, number>, -- (player, s, f, total)
	Fused = Signal.new() :: Signal.Signal<Player, number>, -- (player, étoiles obtenues)

	-- EventService
	EventPhase = Signal.new() :: Signal.Signal<string, string>, -- (événement, phase) ex. ("weather","start")
	CometEvent = Signal.new() :: Signal.Signal<Types.CometSignal>,
	CometParticipation = Signal.new() :: Signal.Signal<Player, string>, -- (player, "hold" | "near" | "crew")
	CometHeld = Signal.new() :: Signal.Signal<Player, number>, -- (player, secondes) à chaque perte/encaissement
	WispPopped = Signal.new() :: Signal.Signal<Player>,
	BeaconResult = Signal.new() :: Signal.Signal<boolean, { Player }>, -- (réussite, contributeurs)

	-- CrewService
	CrewChanged = Signal.new() :: Signal.Signal<{ Player }>, -- joueurs dont l'équipage a changé
	Cheered = Signal.new() :: Signal.Signal<Player, Player>, -- (acclameur, héros)

	-- NestService
	SettingChanged = Signal.new() :: Signal.Signal<Player, string, any>,

	-- QuestService
	RookieEnded = Signal.new() :: Signal.Signal<Player>,

	-- Tous (via Notify.banner) → CrewService (file d'attente et diffusion)
	BannerRequested = Signal.new() :: Signal.Signal<Types.BannerKind, { [string]: any }, Player?>,
}

return Signals
