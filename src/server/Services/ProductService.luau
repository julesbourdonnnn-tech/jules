--!strict
-- ProductService (paquet ranch) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Effets des passes et des produits (GDD §8) par MonetizationService : Squish Party
-- (EventService.startSquishParty ; vendue seulement si elle commence aussitôt, 3 par jour, boost
-- personnel de 10 min si l'acheteur part : accordé dans DataService.onBeforeSave(release = true),
-- jamais dans PlayerRemoving), paquets de pièces (montant calculé à l'attribution, cachés
-- si PolicyService restreint ou si « Grand Splorch prêt ! »), tenues (garde-robe). Passes : Pot
-- automatique, ×2 Pièces, Grand Ranch (EconomyService / SquishyService relisent ownsPass sur
-- PassGranted). PolicyService au chargement (pcall, 3 essais, règle stricte si échec) : attribut
-- Player « PolicyNoCoins ». Clés : aucune (passes : MonetizationService ; caps.partyBuys :
-- EconomyService.consumeCap ; outfits : SquishyService).

local ProductService = {}

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function ProductService.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function ProductService.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Paquets de pièces cachés (PolicyService ou Grand Splorch prêt)
function ProductService.coinsHidden(player: Player): boolean
	local _ = { player }
	error("TODO(ranch): ProductService.coinsHidden")
end

-- Squish Parties achetées aujourd'hui
function ProductService.partyBuysToday(player: Player): number
	local _ = { player }
	error("TODO(ranch): ProductService.partyBuysToday")
end

return ProductService
