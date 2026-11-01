--!strict
-- ProductService (paquet ranch) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Effets des passes et des produits (GDD §8) par MonetizationService : Squish Party
-- (EventService.startSquishParty : démarre, ou PROLONGE de 600 s une fête en cours quand deux reçus se
-- croisent ; 3 par jour ; acheteur parti avant la fin : boost personnel des secondes non jouées de ses
-- achats, EventService.partyUnplayed, accordé dans DataService.onBeforeSave(release = true), jamais
-- dans PlayerRemoving ; fermeture du serveur : idem pour chaque acheteur présent, sauvegardé avant la
-- fermeture), tenues (garde-robe). Paquets de pièces RETIRÉS du lancement (contrat v1.2 : id 0,
-- hidden, aucun handler). Passes : Pot automatique, ×2 Pièces, Grand Ranch (EconomyService /
-- SquishyService relisent ownsPass sur PassGranted). PolicyService au chargement (pcall) : seulement
-- IsContentSharingAllowed (clips, côté client) et l'analytique PolicyPaidRandomRestricted (aucun
-- article caché). Clés : aucune (passes : MonetizationService ; caps.partyBuys :
-- EconomyService.consumeCap ; outfits : SquishyService ; boosts : EconomyService.grantPersonalBoost).

local ProductService = {}

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function ProductService.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function ProductService.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Squish Parties achetées aujourd'hui
function ProductService.partyBuysToday(player: Player): number
	local _ = { player }
	error("TODO(ranch): ProductService.partyBuysToday")
end

return ProductService
