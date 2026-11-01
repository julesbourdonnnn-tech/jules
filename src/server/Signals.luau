--!strict
-- Bus de signaux internes du serveur (repris de Comet Conga).
-- Les services communiquent « vers le haut » de l'ordre d'initialisation (Main.server ORDER) par
-- ces signaux : un service peut émettre ou écouter n'importe lequel, quel que soit son rang, alors
-- qu'un appel direct d'API n'est permis que vers un service initialisé AVANT lui.
-- Chaque signal a UN émetteur (commentaire « émis par ») ; les abonnés se branchent dans Start().
-- Les handlers s'exécutent chacun dans leur propre thread (Shared/Util/Signal) : jamais de yield
-- long dans un handler qui mute un profil sans revérifier DataService.get(player).
-- Socle : signaux génériques seulement ; les paquets du jeu ajoutent les leurs (une ligne chacun).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)

local Signals = {
	-- Émis par le service qui place les personnages : déplacement imposé par le serveur (PivotTo,
	-- apparition) → le service du tick appelle MoveCheck.reset (exemption des paquets « en vol »)
	ServerMoved = Signal.new() :: Signal.Signal<Player>,
	-- Émis par le service qui appelle MoveCheck.step : infraction de déplacement
	-- (player, infractions de la session) → analytique, interface « connexion instable »
	MoveViolation = Signal.new() :: Signal.Signal<Player, number>,
	-- Tous (via Notify.banner) → le service qui tient la file des bannières de serveur (priorité,
	-- durée, débit par joueur source) et la diffuse
	BannerRequested = Signal.new() :: Signal.Signal<Types.BannerKind, { [string]: any }, Player?>,
}

return Signals
