--!strict
-- EventClock (paquet logic) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Phases de chaque événement à l'instant t (UTC), pures et identiques serveur / client (GDD §2.4,
-- §12.4) : Golden Wobbler (:00:30, :10:30, :30:30, :40:30), BOOP RUSH (:05, :15… 90 s, sirène 10 s
-- avant), MEGA SQUISH (:20 et :50, alerte 15 s), Jelly Moon (samedi 16/18/20/22 h, dimanche 16 h, 20
-- min). Un seul grand spectacle fixe à la fois, ≥ 20 s d'écart (vérifié sur 100 000 créneaux).
-- Tests aux instants clés : minuit, :04:50, :05:00, :06:30, :19:45, :20:00, :21:05, samedi
-- 15:59:59, 16:00, 16:20, 22:20, dimanche 16:00, changement de semaine.

local Types = require(script.Parent.Parent.Types)

local EventClock = {}

-- Rush en cours ou prochain (index = numéro global du créneau)
function EventClock.rush(t: number): Types.RushPhase
	local _ = { t }
	error("TODO(logic): EventClock.rush")
end

-- MEGA en cours ou prochain (moon = MEGA MOON SQUISH)
function EventClock.mega(t: number): Types.MegaPhase
	local _ = { t }
	error("TODO(logic): EventClock.mega")
end

-- Golden Wobbler en cours ou prochain
function EventClock.golden(t: number): Types.GoldenPhase
	local _ = { t }
	error("TODO(logic): EventClock.golden")
end

-- Séance de Jelly Moon en cours ou prochaine (session 1-5 dans la semaine)
function EventClock.moon(t: number): Types.MoonPhase
	local _ = { t }
	error("TODO(logic): EventClock.moon")
end

-- Prochain événement pour la pastille du HUD
function EventClock.nextEvent(t: number): Types.NextEvent
	local _ = { t }
	error("TODO(logic): EventClock.nextEvent")
end

-- Rush de :05 ou :15 pendant une séance de Lune (Mythiques et Secrets boopables)
function EventClock.rushMoonBoopable(t: number): boolean
	local _ = { t }
	error("TODO(logic): EventClock.rushMoonBoopable")
end

-- Espèce du géant (rotation du GDD §5.1)
function EventClock.megaSpecies(t: number): number
	local _ = { t }
	error("TODO(logic): EventClock.megaSpecies")
end

-- Graine des trajets d'un événement (Hash)
function EventClock.seed(kind: string, index: number): number
	local _ = { kind, index }
	error("TODO(logic): EventClock.seed")
end

-- Costume de saison actif (Events.Costumes), "" sinon
function EventClock.costume(unix: number): string
	local _ = { unix }
	error("TODO(logic): EventClock.costume")
end

return EventClock
