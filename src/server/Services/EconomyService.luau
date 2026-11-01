--!strict
-- EconomyService (paquet ranch) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Pièces, Pot, croissance cumulée, dalles, multiplicateurs, boosts, Fame, plafonds, hors ligne
-- (GDD §4.1-§4.8, §4.16-§4.19, §4.25, §12.3). Calcul paresseux : settle() règle le Pot (intégrale
-- exacte sur [growth.t ; now], deux Clock.now() : jamais deux fois la même seconde) et avance growth.G
-- à chaque événement qui change g, A, P ou B, avant chaque sauvegarde (onBeforeSave), et toutes les
-- 30 s (décalé par joueur), et aussi à chaque palier de trophée franchi, page dorée, bonus de famille
-- gagné ou changement de Fame (contrat v1.2). Hors ligne : rebase pur et synchrone dans
-- DataService.onPrepare (avant l'instantané et Loaded) : G += Formulas.offlineGrowth (croissance sans
-- boost × Offline.GrowthShare × durée, arrêtée à Offline.StopAt × objectif(R) pour le plus gros),
-- Pot += revenu de départ sans boost × 25 % × durée (8 h au plus), growth.t = Clock.now() ; écran de
-- retour (Celebrate "return") si ≥ 10 min, sur Loaded. Départ : onBeforeSave(release = true) règle et
-- pose lastOnline. Dalles : achat sur la dalle après Tiles.DwellSeconds (crochet "pad" de RanchService)
-- ou □ / panneau (BuyTile), prix × Tiles.RScale^R pour les dalles de la boucle. Grand Splorch appliqué
-- d'un bloc (applySplorch). Analytics économie (§16.2) cumulées par joueur, tranche de 5 min et
-- itemSku, en secondes de revenu (note INT-ANALYTICS). Émet TileBought, PotCollected. Remotes :
-- BuyTile. Clés : lastOnline, coins, pot, R, growth, tiles, fame, boosts, caps.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Formulas = require(Shared.Logic.Formulas)

local EconomyService = {}

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function EconomyService.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function EconomyService.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Tick : règlements échelonnés (30 s), fins de boost, Pot automatique (pass, 5 s)
function EconomyService.step(now: number)
	local _ = { now }
	error("TODO(ranch): EconomyService.step")
end

-- Règle le Pot et la croissance cumulée jusqu'à maintenant
function EconomyService.settle(player: Player)
	local _ = { player }
	error("TODO(ranch): EconomyService.settle")
end

-- settle puis recalcule g, A, P, B (après un changement) et publie growth (RanchService.setPublic)
function EconomyService.refresh(player: Player)
	local _ = { player }
	error("TODO(ranch): EconomyService.refresh")
end

-- Pièces actuelles (après settle)
function EconomyService.coins(player: Player): number
	local _ = { player }
	error("TODO(ranch): EconomyService.coins")
end

-- Crédite (borné, entier) ; rend le montant crédité ; analytics source
function EconomyService.addCoins(player: Player, amount: number, sku: string, txType: string?): number
	local _ = { player, amount, sku, txType }
	error("TODO(ranch): EconomyService.addCoins")
end

-- Débite si assez (après settle) ; analytics puits
function EconomyService.trySpend(player: Player, amount: number, sku: string): boolean
	local _ = { player, amount, sku }
	error("TODO(ranch): EconomyService.trySpend")
end

-- Revenu actuel du joueur (enclos + Bassin, multiplicateurs compris)
function EconomyService.income(player: Player): number
	local _ = { player }
	error("TODO(ranch): EconomyService.income")
end

-- Revenu actuel d'un squishy
function EconomyService.squishyIncome(player: Player, uid: string): number
	local _ = { player, uid }
	error("TODO(ranch): EconomyService.squishyIncome")
end

-- Récompense « en secondes de revenu » ; rend le montant
function EconomyService.addIncomeSeconds(
	player: Player,
	seconds: number,
	sku: string,
	minimum: number?
): number
	local _ = { player, seconds, sku, minimum }
	error("TODO(ranch): EconomyService.addIncomeSeconds")
end

-- Croissance cumulée du ranch (lecture)
function EconomyService.growth(player: Player): Types.Growth
	local _ = { player }
	error("TODO(ranch): EconomyService.growth")
end

-- G(t) du ranch
function EconomyService.G(player: Player, t: number?): number
	local _ = { player, t }
	error("TODO(ranch): EconomyService.G")
end

-- Achète le niveau suivant (condition R, prix × Tiles.RScale^R si la dalle suit R) ; refus doux sur une dalle (anneau)
function EconomyService.buyTile(player: Player, tile: string, source: "pad" | "panel"): boolean
	local _ = { player, tile, source }
	error("TODO(ranch): EconomyService.buyTile")
end

-- Encaisse le Pot ; rend le montant
function EconomyService.collectPot(player: Player, auto: boolean): number
	local _ = { player, auto }
	error("TODO(ranch): EconomyService.collectPot")
end

-- Niveau de Grand Splorch
function EconomyService.R(player: Player): number
	local _ = { player }
	error("TODO(ranch): EconomyService.R")
end

-- Fame bornée par les plafonds du jour ; rend la Fame accordée
function EconomyService.addFame(
	player: Player,
	amount: number,
	source: "rush" | "release" | "splorch" | "mega"
): number
	local _ = { player, amount, source }
	error("TODO(ranch): EconomyService.addFame")
end

-- Plafond journalier (Balance.Caps) : rend la part accordée (0 = plafond atteint)
function EconomyService.consumeCap(player: Player, capKey: string, wanted: number): number
	local _ = { player, capKey, wanted }
	error("TODO(ranch): EconomyService.consumeCap")
end

-- Boost personnel ×2 (secondes ajoutées, en pause pendant un boost de serveur)
function EconomyService.grantPersonalBoost(player: Player, seconds: number)
	local _ = { player, seconds }
	error("TODO(ranch): EconomyService.grantPersonalBoost")
end

-- Boost de serveur poussé par EventService ("wobble", "squish", "admin", "")
function EconomyService.setServerBoost(kind: string, untilT: number)
	local _ = { kind, untilT }
	error("TODO(ranch): EconomyService.setServerBoost")
end

-- B = 2 pour ce joueur
function EconomyService.boostActive(player: Player): boolean
	local _ = { player }
	error("TODO(ranch): EconomyService.boostActive")
end

-- Amis Roblox présents (poussé par CommunityService)
function EconomyService.setFriendsPresent(player: Player, count: number)
	local _ = { player, count }
	error("TODO(ranch): EconomyService.setFriendsPresent")
end

-- Plafond journalier PAR AMI (caps.petSitBy[tostring(friendUserId)], Balance.CapsPerFriend[capKey]) :
-- rend la part accordée (0 = plafond atteint) ; remis à zéro avec caps au changement de jour UTC
function EconomyService.consumeFriendCap(
	player: Player,
	capKey: string,
	friendUserId: number,
	wanted: number
): number
	local _ = { player, capKey, friendUserId, wanted }
	error("TODO(ranch): EconomyService.consumeFriendCap")
end

-- Croissance par seconde SANS boost (Formulas.growthRate avec boost = false) : bonus du Rush
-- (SquishyService.growFor), hors ligne
function EconomyService.gNoBoost(player: Player): number
	local _ = { player }
	error("TODO(ranch): EconomyService.gNoBoost")
end

-- Grand Splorch d'un bloc : pièces, Pot, Tapis, décorations à 0, R + 1, Fame + 5, G = 0 ; rend les pièces perdues
function EconomyService.applySplorch(player: Player): number
	local _ = { player }
	error("TODO(ranch): EconomyService.applySplorch")
end

-- Crochet appelé après chaque settle avec G (SquishyService : trophées, record)
function EconomyService.onSettle(fn: (Player, number) -> ())
	local _ = { fn }
	error("TODO(ranch): EconomyService.onSettle")
end

-- Contexte des multiplicateurs (lecture)
function EconomyService.incomeCtx(player: Player): Formulas.IncomeCtx
	local _ = { player }
	error("TODO(ranch): EconomyService.incomeCtx")
end

return EconomyService
