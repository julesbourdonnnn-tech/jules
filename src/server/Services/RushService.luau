--!strict
-- RushService (paquet chase) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- BOOP RUSH côté serveur (GDD §4.21) : mode Rush / Cozy (Cozy d'office ; passage en Cozy immédiat,
-- passage en Rush après 60 s et à la fin du Rush en cours ; serveurs privés en Cozy sauf autorisation
-- du propriétaire), carte du choix (ModePrompt une fois, dès 15:00 de jeu), bouclier débutant (15 min
-- de jeu cumulé), clôtures (4 ou 2 squishies, renouvelés toutes les 20 s, RanchService.setFence),
-- maintiens de boop mesurés par le serveur (2,5 / 5 s, grâce 0,5 s, règles revérifiées à chaque tick
-- dont BoopCtx.eligible : un squishy qui quitte l'enclos annule le maintien ; extendHold une seule
-- fois par maintien),
-- protections (paires 30 min, 1 boop / 20 s, 2 par ranch et par Rush, 4 par heure, 10 sur le serveur,
-- « Pas ce joueur », liste de blocage souple), carte d'après le premier boop. Émet Booped,
-- ModeChanged. Remotes : BoopHold, SetMode, RefuseBooper ; BoopState, ModePrompt. Clé : mode.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)

local RushService = {}

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function RushService.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function RushService.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Tick : clôtures, maintiens de boop finis ou rompus, carte du choix au calme
function RushService.step(now: number, actors: { [Player]: Types.TickActor })
	local _ = { now, actors }
	error("TODO(chase): RushService.step")
end

-- Mode effectif Rush
function RushService.isRush(player: Player): boolean
	local _ = { player }
	error("TODO(chase): RushService.isRush")
end

-- Bouclier débutant actif
function RushService.isShielded(player: Player): boolean
	local _ = { player }
	error("TODO(chase): RushService.isShielded")
end

-- Ranch boopable maintenant (badge rose)
function RushService.canBeBooped(owner: Player): boolean
	local _ = { owner }
	error("TODO(chase): RushService.canBeBooped")
end

-- BOOP RUSH autorisé sur ce serveur (serveur privé)
function RushService.allowRush(): boolean
	error("TODO(chase): RushService.allowRush")
end

-- États minutés ouverts (débogage, robot de longue durée : docs/04 §17.2 invariant 6) : « boopHold » (maintiens), « modeCard » (carte du choix envoyée, sans réponse), « rush » ;
-- noms de StateTimeouts.names(), startedAt en Clock.now()
function RushService.openStates(): { Types.OpenState }
	error("TODO(chase): RushService.openStates")
end

return RushService
