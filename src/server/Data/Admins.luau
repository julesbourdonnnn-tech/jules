--!strict
-- Administrateurs LiveOps (données serveur, jamais répliquées). UserIds autorisés à envoyer les
-- commandes d'administration (ex. « Squish Party » annoncée, événements) ; chaque commande est
-- revérifiée côté serveur. Liste vide = LiveOps désactivé.
-- Ajouter un administrateur : [UserId] = true (avant publication, jamais côté client).

local Admins: { [number]: boolean } = {}

return Admins
