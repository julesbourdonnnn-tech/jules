--!strict
-- QuestService — paquet « events » (STUB du contrat : docs/04-architecture.md §11.10).
-- Propriétaire de : onboarding, daily (calendrier), quests (du jour), weekly, rookie, stats, codes.
-- Suit la progression en écoutant les signaux serveur (Signals.*), jamais en interrogeant les
-- services plus tardifs.
-- Responsabilités :
--   * chaîne d'accueil Q1-Q7 (Config/Quests.Onboarding) : récompense AUTOMATIQUE à la complétion,
--     Celebrate "questDone", étape d'entonnoir ; au premier chargement (step 0) : SpawnService.spawnWelcome
--     et setDirected pendant Q1-Q3 ; Q4 : SpawnService.spawnGuaranteedRare (une fois par compte)
--   * entonnoir d'accueil (§14.1) : TOUTES les étapes 1-10 sont envoyées ici (Analytics.funnel)
--   * quêtes du jour : tirage déterministe Hash(jour, UserId) d'1 facile, 1 moyenne, 1 difficile
--     (JcJ exclues en Zen, Équipage seulement si stats.lastCrewDay ≥ jour − 7) ; relance gratuite
--     (+1 VIP) ; remise à zéro à 00:00 UTC ; récompenses par niveau ; « Étoile du jour » (boost 15 min)
--   * quête hebdomadaire Grand Défilé (300 Nebbies encaissés → Légendaire de la semaine + 300)
--   * calendrier de 7 jours indulgent (un jour manqué = pause) ; remote ClaimDaily 1/s
--   * remotes ClaimQuest(kind, slot) 4/s, RerollQuest(slot) 1/s, RedeemCode(code) 1/3 s et 10/h
--     (Data/Codes ; une fois par compte ; statut "ok" | "invalid" | "expired" | "used" | "busy")
--   * bouclier débutant (Formulas.rookieEligible) : isRookie() ; fin jamais en pleine course —
--     attendue jusqu'à onSafeMoment (parade ou file vide, appelé par CongaService) ; bannière
--     personnelle « rookieEnd », attribut Player « Rookie », Signals.RookieEnded, Analytics RookieShieldEnded
--   * statistiques (clé « stats ») et temps de jeu (step) ; titres de statistiques via NestService.unlock
-- GDD : §3, §4.16, §7.3-§7.5, §14.1, §4.17 (codes).
-- Dépendances : DataService, MonetizationService, NestService, EconomyService, AtlasService,
-- SpawnService, EventService, CrewService, Logic/Hash, Logic/Formulas, Logic/EventClock,
-- Config/Quests, Data/Codes, Signals, Util/Notify, Util/RateLimit, Util/Analytics, Shared/Util/Clock.

local QuestService = {}

function QuestService.Init() end

function QuestService.Start() end

-- Temps de jeu, fin de bouclier différée, changement de jour UTC
function QuestService.step(_now: number)
	error("TODO(events): QuestService.step")
end

-- Bouclier débutant actif (file incoupable, coupes sans Stardust)
function QuestService.isRookie(_player: Player): boolean
	error("TODO(events): QuestService.isRookie")
end

-- Moment sûr (parade ou file vide) : termine le bouclier si sa fin est due
function QuestService.onSafeMoment(_player: Player)
	error("TODO(events): QuestService.onSafeMoment")
end

-- Étape d'accueil courante (0 pas commencé, 1-7, 8 terminé)
function QuestService.onboardingStep(_player: Player): number
	error("TODO(events): QuestService.onboardingStep")
end

-- Ids des 3 quêtes du jour (tirage déterministe, avant relances)
function QuestService.drawDaily(_userId: number, _day: number, _zen: boolean, _crewRecent: boolean): { number }
	error("TODO(events): QuestService.drawDaily")
end

-- Applique un code ; retourne le statut
function QuestService.redeem(_player: Player, _code: string): string
	error("TODO(events): QuestService.redeem")
end

return QuestService
