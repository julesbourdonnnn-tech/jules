--!strict
-- ProductService — paquet « economy » (STUB du contrat : docs/04-architecture.md §11.11).
-- Effets de TOUS les passes et produits, branchés sur MonetizationService (aucun ProcessReceipt ici).
-- Responsabilités :
--   * Init : MonetizationService.registerProduct pour chaque clé de Config/Monetization.Products ;
--     chaque handler retourne true seulement si l'effet est appliqué (profil chargé) ;
--     montants Glow calculés par le serveur AU MOMENT DE L'ATTRIBUTION (idleSeconds, minGlow)
--   * GlowParty : EventService.queueGlowParty(buyer, 600) (jamais refusé : un reçu payé est
--     toujours honoré, même au-delà de la file de 60 min en cas de course) + bannière glowParty
--   * StardustJar : +400 ; StarterKit : 3 Rares (AtlasService), style comet_tail (NestService.unlock),
--     boost 20 min, profile.starterKit = true (une seconde vente éventuelle est quand même honorée)
--   * passes (MonetizationService.PassGranted, y compris à l'arrivée) : VIPStar / DoubleGlow →
--     EconomyService.settle + refreshRate ; ExtraPerches → AtlasService.refreshPerches ;
--     StashPlus, NightShift, CongaStyles : lus dynamiquement (rien à stocker)
--   * Celebrate "purchase" (pluie de pièces, « Merci ! ») ; Analytics Product_<clé>
-- GDD : §8.2, §8.3, §8.1 (déterministe, prix lus à l'exécution côté client), §14.2.
-- Dépendances : DataService, MonetizationService, NestService, EconomyService, AtlasService,
-- EventService, Config/Monetization, Config/Balance, Util/Notify, Util/Analytics.

local ProductService = {}

function ProductService.Init() end

function ProductService.Start() end

-- Glow qu'accorderait maintenant un produit Glow (affichage « ≈ » côté client : même calcul)
function ProductService.glowAmount(_player: Player, _productKey: string): number
	error("TODO(economy): ProductService.glowAmount")
end

-- Applique l'effet d'un produit (handler partagé, exposé pour les tests) ; true si appliqué
function ProductService.grant(_player: Player, _productKey: string): boolean
	error("TODO(economy): ProductService.grant")
end

return ProductService
