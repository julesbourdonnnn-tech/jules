--!strict
-- Administrateurs LiveOps (GDD §7.6) — paquet « events » (données serveur, jamais répliquées).
-- UserIds autorisés à envoyer le remote AdminCommand (EventService), qui publie la commande sur
-- le sujet MessagingService « LiveOps » pour tous les serveurs. Liste vide = LiveOps désactivé.
-- Ajouter un administrateur : [UserId] = true (avant publication, jamais côté client).

local Admins: { [number]: boolean } = {}

return Admins
