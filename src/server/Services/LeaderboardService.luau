--!strict
-- LeaderboardService — paquet « events » (STUB du contrat : docs/04-architecture.md §11.12).
-- Propriétaire de la clé de profil « weeklyBest » et des classements.
-- Responsabilités :
--   * tableau du serveur (mémoire) : top 5 des congas en cours (Signals.LineChanged), mis à jour
--     chaque seconde ; record de parade du serveur (Signals.Parade) → bannière serverRecord ;
--     écrit sur la stèle (WorldService.board()) les attributs Live / Record / Weekly
--     (format "userId:name:n;userId:name:n…", noms Roblox Name)
--   * classements mondiaux : OrderedDataStore "WeeklyConga_<w>" (plus longue parade de la semaine) et
--     "AtlasAllTime" (entrées d'Atlas) ; écritures quand un joueur bat son record (file par serveur
--     vidée toutes les 60 s, en task.spawn + pcall + retries), lecture du top 10 toutes les 120 s ;
--     joueurs flags.lbBanned jamais écrits
--   * titre « Roi / Reine de la Conga » : à l'arrivée, top 10 de la semaine précédente →
--     NestService.grantTemporary(player, "titles", "conga_royal")
--   * aucune boucle propre : step(now) est appelé par le tick de CongaService ; les appels
--     DataStore se font en task.spawn (jamais de yield dans step)
-- GDD : §6.4 (tableau), §6.7, §12.8 (budget DataStore).
-- Dépendances : DataService, NestService, WorldService, Signals, Util/Notify, Config/Balance,
-- Shared/Util/Clock.

local LeaderboardService = {}

export type BoardEntry = { userId: number, name: string, n: number }

function LeaderboardService.Init() end

function LeaderboardService.Start() end

function LeaderboardService.step(_now: number)
	error("TODO(events): LeaderboardService.step")
end

function LeaderboardService.liveTop(): { BoardEntry }
	error("TODO(events): LeaderboardService.liveTop")
end

function LeaderboardService.serverRecord(): BoardEntry?
	error("TODO(events): LeaderboardService.serverRecord")
end

function LeaderboardService.weeklyTop(): { BoardEntry }
	error("TODO(events): LeaderboardService.weeklyTop")
end

return LeaderboardService
