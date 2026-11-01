--!strict
-- Déclaration de TOUS les remotes du jeu : nom → type ("event" | "unreliable" | "func").
-- Net.setup() les crée côté serveur ; Net.event("Nom") les récupère partout (une faute de frappe
-- dans un nom lève une erreur claire). Registre partagé : ajouts ciblés autorisés (une ligne par
-- remote, son type, sa charge utile et son propriétaire en commentaire ; jamais de renommage).
-- Socle : seuls les remotes des modules du socle. Les paquets du jeu ajoutent les leurs.
-- Règle : un remote client → serveur porte une INTENTION, jamais une valeur de jeu ; le serveur
-- valide chaque argument (Shared/Util/Validate) et limite le débit (Server/Util/RateLimit).

return {
	-- Données joueur (DataService ↔ StateController)
	DataSnapshot = "event", -- serveur → client : état complet (clés privées retirées)
	DataPatch = "event", -- serveur → client : (patch, removedKeys, entries?: Types.DataPatchEntries)
	RequestSnapshot = "event", -- client → serveur : () redemande l'état complet (2 / 10 s)

	-- Retours au joueur (Server/Util/Notify)
	Feedback = "event", -- serveur → client : (Types.FeedbackPayload)
	Celebrate = "event", -- serveur → client : (Types.CelebratePayload)
	Banner = "event", -- serveur → client : (Types.BannerPayload)
} :: { [string]: string }
