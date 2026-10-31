--!strict
-- Loading — paquet « world » (STUB du contrat : docs/04-architecture.md §13.5).
-- LocalScript de ReplicatedFirst : écran de chargement construit en code, AUTONOME (n'exige rien
-- de ReplicatedStorage : il s'affiche avant la réplication).
-- Responsabilités :
--   * ReplicatedFirst:RemoveDefaultLoadingScreen() puis ScreenGui plein écran (IgnoreGuiInset,
--     DisplayOrder élevé, ResetOnSpawn = false) : un Nebby en Frames qui rebondit + 3 points animés,
--     aucun texte long ; Mouvement réduit respecté (GuiService.ReducedMotionEnabled)
--   * disparition (fondu 0,3 s) quand game:IsLoaded() ET que l'attribut LOCAL
--     Players.LocalPlayer « ClientReady » vaut true (posé par UI/HUD, paquet client-hud, une fois
--     l'instantané de profil reçu et le HUD construit — voir §13.5) ; attentes toujours bornées
--   * après 20 s sans profil : « Ton Nid se réveille… » (FR/EN selon LocaleId, textes embarqués car
--     Localization n'est pas encore répliqué) + bouton Réessayer (TeleportService:Teleport(PlaceId))
-- GDD : §3 (chargement), §10.3 (écrans Chargement / Échec), §12.2.
-- Dépendances : aucune (services Roblox uniquement).

-- STUB : ne fait rien tant que le paquet « world » ne l'a pas implémenté.
local _ = script
