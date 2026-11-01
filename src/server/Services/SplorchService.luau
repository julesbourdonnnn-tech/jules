--!strict
-- SplorchService (paquet chase) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Grand Splorch (GDD §4.15, §6.7) : entrée dans la file (GrandSplorch : plus gros ≥ objectif, dans
-- son ranch, rien de porté ; vérifié UNE seule fois puis garanti), squishy en attente (tremble, ni
-- boopable ni vendable), départ par Signals.SpectacleStarted, application au profil d'un bloc à
-- l'éclatement (3,2 s, minuteur du serveur : EconomyService.applySplorch, SquishyService.resetSizes,
-- trophées), sauvegarde immédiate, cadeaux aux autres joueurs (60 s de revenu + 1 bébé, plafonds,
-- réglage « Recevoir les cadeaux »), fenêtre d'applaudissement (CommunityService), bannière,
-- célébration pour tous. Départ avant son tour : place rendue, rien remis à zéro. Émet
-- Splorched(héros, nouveau R, bébés-cadeaux donnés) ; jamais EventService.addGauge (la jauge vient
-- de Splorched).
-- Remote : GrandSplorch. Clés : aucune.

local SplorchService = {}

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function SplorchService.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function SplorchService.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Tick : éclatement dû, fin du spectacle (coupure dure à 10 s)
function SplorchService.step(now: number)
	local _ = { now }
	error("TODO(chase): SplorchService.step")
end

-- Clock.now() de départ prévu si le joueur est dans la file
function SplorchService.queued(player: Player): number?
	local _ = { player }
	error("TODO(chase): SplorchService.queued")
end

-- Ce squishy attend son Grand Splorch
function SplorchService.isWaiting(player: Player, uid: string): boolean
	local _ = { player, uid }
	error("TODO(chase): SplorchService.isWaiting")
end

-- États minutés ouverts (débogage, robot de longue durée : docs/04 §17.2 invariant 6) : « splorchQueue » (en file), « splorchBurst » (éclatement dû) ;
-- noms de StateTimeouts.names(), startedAt en Clock.now()
function SplorchService.openStates(): { { name: string, startedAt: number, player: Player? } }
	error("TODO(chase): SplorchService.openStates")
end

return SplorchService
