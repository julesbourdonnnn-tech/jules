--!strict
-- LeaderboardService (paquet meta) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Classements de la semaine (GDD §6.9) : 5 catégories (tampons, combo, capture, serviable,
-- généreux), égalités au premier arrivé, OrderedDataStore Weekly_<clé>_<semaine> (écritures groupées
-- toutes les 60 s, top 10 lu toutes les 120 s, jamais dans le thread du tick), record de la semaine
-- passée (weekly.prev), remise à zéro le lundi 00:00 UTC, titres du top 10 pour la semaine suivante,
-- exclusion des joueurs bannis (flags.lbBanUntil). Nom caché respecté partout : valeur écrite =
-- valeur × 2 + (caché ? 1 : 0), décodée à la lecture ; caché ou inconnu → name = "" (alias côté
-- client) ; noms résolus par UserService:GetUserInfosByUserIdsAsync (pcall, task.spawn, cache de la
-- semaine). Titres du top 10 accordés par CommunityService.unlockSession. Tableau du serveur en direct
-- et statue du plus gros squishy du serveur (WorldService.setStatue, nom caché respecté).
-- Remote : LeaderboardState.
-- Clé : weekly.

local LeaderboardService = {}

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function LeaderboardService.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function LeaderboardService.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Tick : files d'écriture (60 s), lectures (120 s), statue, changement de semaine
function LeaderboardService.step(now: number)
	local _ = { now }
	error("TODO(meta): LeaderboardService.step")
end

-- Nouvelle valeur de la semaine (écrite si record battu)
function LeaderboardService.submit(player: Player, category: string, value: number)
	local _ = { player, category, value }
	error("TODO(meta): LeaderboardService.submit")
end

-- Exclu des classements jusqu'à flags.lbBanUntil
function LeaderboardService.isBanned(player: Player): boolean
	local _ = { player }
	error("TODO(meta): LeaderboardService.isBanned")
end

return LeaderboardService
