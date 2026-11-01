--!strict
-- CommunityService (paquet meta) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Social sans chat (GDD §6) : amis Roblox présents (bonus de revenu poussé à EconomyService, ranchs
-- voisins), pet-sitting (clôture d'un ami à ≤ 10 studs : 3 squishies prêts, PetPress ; 100 récompensées
-- par jour et par visiteur (2 s de revenu, ×2 PERFECT), 100 reçues par propriétaire, « Plus serviable » :
-- 20 par ami et par jour), réception de la liste de blocage (ReportBlocked, envoyée une fois par
-- WorldStateController.Start depuis StarterGui:GetCore("GetBlockedUserIds") sous pcall),
-- emotes de la croix (EmoteShow, 1 / 1,2 s), applaudissements du Grand Splorch (8 s, 10 récompensés
-- / jour), file des bannières de serveur (Signals.BannerRequested : priorité Events.Banners, 3 au
-- plus, 10 s par joueur source, nouveaux avant l'étape 9), réglages (SetSetting, Config/Settings),
-- nom caché (alias), cosmétiques équipés, liste de blocage souple (ReportBlocked, 200 ids).
-- Remplit Notify.BANNER_PRIORITY depuis Config/Events à Init. Déblocages de session (titres de la
-- semaine : unlockSession). Émet Emoted, SettingChanged, FriendsChanged, PetSitRewarded. Remotes :
-- PetPress, SetSetting, EquipCosmetic, Emote, Clap, ReportBlocked ; EmoteShow, ClapPrompt, Banner.
-- Clés : settings, cosmetics.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)

local CommunityService = {}

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function CommunityService.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function CommunityService.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Tick : clôtures de pet-sitting, fenêtres d'applaudissement, file des bannières
function CommunityService.step(now: number, actors: { [Player]: Types.TickActor })
	local _ = { now, actors }
	error("TODO(meta): CommunityService.step")
end

-- Nom d'affichage, ou alias « Squishy Fan #NNNN » si caché (clé de texte côté client)
function CommunityService.displayName(player: Player): string
	local _ = { player }
	error("TODO(meta): CommunityService.displayName")
end

-- Amis Roblox présents (mis en cache)
function CommunityService.friendsPresent(player: Player): number
	local _ = { player }
	error("TODO(meta): CommunityService.friendsPresent")
end

-- Amis Roblox (cache de session)
function CommunityService.areFriends(a: Player, b: Player): boolean
	local _ = { a, b }
	error("TODO(meta): CommunityService.areFriends")
end

-- L'un a bloqué l'autre (liste souple fournie par le client)
function CommunityService.isBlocked(a: Player, b: Player): boolean
	local _ = { a, b }
	error("TODO(meta): CommunityService.isBlocked")
end

-- Réglage du joueur (Config/Settings) ou du serveur (allowRush)
function CommunityService.setting(player: Player, key: string): any
	local _ = { player, key }
	error("TODO(meta): CommunityService.setting")
end

-- Fenêtre APPLAUDIR de 8 s : ClapPrompt aux seuls `viewers` (spectateurs du spectacle complet, choisis
-- par SplorchService ; nil = tous les autres joueurs) ; le client la cache pendant une poursuite, un
-- maintien ou une fenêtre ouverte
function CommunityService.openClapWindow(hero: Player, endsAt: number, viewers: { Player }?)
	local _ = { hero, endsAt, viewers }
	error("TODO(meta): CommunityService.openClapWindow")
end

-- Cosmétique débloqué (source de Config/Cosmetics)
function CommunityService.hasCosmetic(player: Player, kind: string, id: string): boolean
	local _ = { player, kind, id }
	error("TODO(meta): CommunityService.hasCosmetic")
end

-- États minutés ouverts (débogage, robot de longue durée : docs/04 §17.2 invariant 6) : « clapWindow » (fenêtres d'applaudissement) ;
-- noms de StateTimeouts.names(), startedAt en Clock.now()
function CommunityService.openStates(): { Types.OpenState }
	error("TODO(meta): CommunityService.openStates")
end

-- Déblocage d'un cosmétique pour la session (titres du top 10 de la semaine, source "weekly") :
-- appelé par LeaderboardService au changement de semaine et à l'arrivée ; hasCosmetic le voit aussitôt
function CommunityService.unlockSession(player: Player, kind: string, id: string)
	local _ = { player, kind, id }
	error("TODO(meta): CommunityService.unlockSession")
end

return CommunityService
