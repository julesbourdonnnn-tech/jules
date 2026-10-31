--!strict
-- LightingController — paquet « world » (STUB du contrat : docs/04-architecture.md §13.4).
-- Ambiance animée CÔTÉ CLIENT à partir de l'horloge commune, sans réplication.
-- Responsabilités :
--   * cycle crépuscule ↔ nuit de 12 min : ClockTime = 17,6 + 2,9 × (0,5 − 0,5 cos(2π t / 720)),
--     t = Clock.now() (Events.Lighting.Cycle), une seule connexion RenderStepped
--   * préréglages météo (Events.Lighting.Presets, tween de 3 s Sine InOut, retour en 3 s) et leurs
--     effets clients : rideaux d'aurore (Beam), neige (ParticleEmitter sur une pièce qui suit la
--     caméra), traits de météores (réserve de 10), arcs arc-en-ciel, teinte HSV ; Eclipse (v1.1)
--   * Nuit de la Balise (ClockTime 21,5 en 4 s, StarCount 5000, anneaux "BeaconRing" allumés un à un,
--     faisceau ×3, anneau "BeaconDeposit"), alerte Comète (OutdoorAmbient −30 % en 2 s),
--     éclairage doré pendant la Nuit d'Or
--   * sources : EventClock (météo, Balise, Starfall : déterministes) et WorldStateController
--     (réussite de la Balise, Nuit d'Or, Comète, LiveOps)
--   * Graphismes légers (Prefs.lowGraphics) : effets réduits ; Mouvement réduit : pas de flash
-- GDD : §11.5, §9.4 (Météo, Balise, Comète), §9.1 (réglages).
-- Dépendances : StateController, Util/Prefs, WorldStateController, Logic/EventClock, Config/Events,
-- Shared/Util/Clock, UI/Juice.

local LightingController = {}

function LightingController.Init() end

function LightingController.Start() end

-- ClockTime du cycle à l'instant t (pur)
function LightingController.cycleClockTime(_t: number): number
	error("TODO(world): LightingController.cycleClockTime")
end

-- Préréglage actif ("aurora", "beacon", … ou nil)
function LightingController.currentPreset(): string?
	error("TODO(world): LightingController.currentPreset")
end

-- Force un préréglage (tests, LiveOps) ; nil = retour au cycle
function LightingController.setPreset(_key: string?)
	error("TODO(world): LightingController.setPreset")
end

return LightingController
