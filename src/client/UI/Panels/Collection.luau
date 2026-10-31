--!strict
-- Panels/Collection — paquet « client-panels » (STUB du contrat : docs/04-architecture.md §13.16).
-- Module de panneau (interface PanelController.Panel), construit à la première ouverture.
-- Responsabilités :
--   * onglets Perchoirs (perchés + revenu de chacun), Réserve (grille VIRTUALISÉE : seules les cases
--     visibles existent ; tri ; verrou → SetLock ; libération en lot → Release(uids) avec
--     confirmation et total de Stardust), Forge (fusions possibles en haut → Fuse(uid),
--     « Tout fusionner » → FuseAll ; animation Starforge sur Celebrate "starforge"),
--     Atlas (grille espèces × formes, silhouettes grises, jalons, « NOUVEAU ! »), Guide
--     (probabilités par zone, météo, Comète, variantes : lues dans Config, rien en dur)
--   * icônes de Nebbies : NebbyBuilder dans des ViewportFrame réutilisés, ou pastilles en Frames
--   * débloqué après Q4 (profil onboarding) ; hasAction : une fusion est possible
--   * textes via Prefs.t (ré-appliqués sur Prefs.LanguageChanged), nombres via Prefs.number,
--     boutons Juice.press + Selectable ; intentions seulement (le serveur valide tout)
-- GDD : §4.9, §4.13, §4.14, §4.3 (probabilités affichées), §9.4 (Starforge, Atlas, Libération), §10.3.
-- Dépendances : StateController, Util/Prefs, UI/Theme, UI/Create, UI/Juice, Shared/Net, Logic/Formulas,
-- Config/*, WorldStateController, ScreenFX, Shared/Util/Clock.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared").Types)

local Panel = {}

Panel.name = "Collection" :: Types.PanelName
Panel.tabs = { "collection.tab.perches", "collection.tab.stash", "collection.tab.forge", "collection.tab.atlas", "collection.tab.guide" } :: { string }?

function Panel.build(_parent: Frame)
	error("TODO(client-panels): Collection.build")
end

function Panel.onOpen(_args: any?)
	error("TODO(client-panels): Collection.onOpen")
end

function Panel.onClose()
	error("TODO(client-panels): Collection.onClose")
end

function Panel.hasAction(): boolean
	error("TODO(client-panels): Collection.hasAction")
end

function Panel.selectTab(_tab: string)
	error("TODO(client-panels): Collection.selectTab")
end

return Panel
