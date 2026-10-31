--!strict
-- Panels/Goals — paquet « client-panels » (STUB du contrat : docs/04-architecture.md §13.16).
-- Module de panneau (interface PanelController.Panel), construit à la première ouverture.
-- Responsabilités :
--   * Aujourd'hui : 3 quêtes (profile.quests), barres, Réclamer → ClaimQuest("daily", slot),
--     relance → RerollQuest(slot), « Étoile du jour » ; minuteur jusqu'à 00:00 UTC (Clock)
--   * Calendrier : 7 cartes (Config/Quests.Calendar), carte qui se retourne, points de série,
--     Réclamer → ClaimDaily ; « en pause » expliqué (un jour manqué ne fait rien perdre)
--   * Semaine : Grand Défilé (profile.weekly, Légendaire de la semaine via EventClock.rotation)
--     → ClaimQuest("weekly", 1)
--   * Accueil : quête Q1-Q7 en cours (tant que non finie)
--   * hasAction : une récompense est réclamable
--   * textes via Prefs.t (ré-appliqués sur Prefs.LanguageChanged), nombres via Prefs.number,
--     boutons Juice.press + Selectable ; intentions seulement (le serveur valide tout)
-- GDD : §7.3, §7.4, §7.5, §9.4 (Calendrier, Quête), §10.3.
-- Dépendances : StateController, Util/Prefs, UI/Theme, UI/Create, UI/Juice, Shared/Net, Logic/Formulas,
-- Config/*, WorldStateController, ScreenFX, Shared/Util/Clock.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared").Types)

local Panel = {}

Panel.name = "Goals" :: Types.PanelName
Panel.tabs = { "goals.tab.today", "goals.tab.calendar", "goals.tab.week", "goals.tab.welcome" } :: { string }?

function Panel.build(_parent: Frame)
	error("TODO(client-panels): Goals.build")
end

function Panel.onOpen(_args: any?)
	error("TODO(client-panels): Goals.onOpen")
end

function Panel.onClose()
	error("TODO(client-panels): Goals.onClose")
end

function Panel.hasAction(): boolean
	error("TODO(client-panels): Goals.hasAction")
end

function Panel.selectTab(_tab: string)
	error("TODO(client-panels): Goals.selectTab")
end

return Panel
