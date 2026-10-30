--!strict
-- Déclaration de TOUS les remotes du jeu : nom → type ("event" | "unreliable" | "func").
-- Net.setup() les crée côté serveur ; Net.event("Nom") les récupère partout.

return {
	-- Données joueur (DataService ↔ StateController)
	DataSnapshot = "event", -- serveur → client : état complet
	DataPatch = "event", -- serveur → client : (patch, removedKeys)
	RequestSnapshot = "event", -- client → serveur : redemande l'état complet
} :: { [string]: string }
