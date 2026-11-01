--!strict
-- PressTiming (paquet logic) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Phase du rebond et fenêtre PERFECT (GDD §4.7) : période 1,2 s calée sur Clock.now() et un décalage
-- propre au squishy (Hash du propriétaire et de l'uid), donc identique côté client et serveur.
-- Fenêtre de 0,08 s avant à 0,20 s après le sommet (retard des télés) ; tClient borné.

local PressTiming = {}

-- Décalage du rebond dans [0 ; Period[
function PressTiming.offset(ownerId: number, uid: string): number
	local _ = { ownerId, uid }
	error("TODO(logic): PressTiming.offset")
end

-- Phase dans [0 ; 1[ (0 = sommet)
function PressTiming.phase(t: number, offset: number): number
	local _ = { t, offset }
	error("TODO(logic): PressTiming.phase")
end

-- t est dans la fenêtre PERFECT
function PressTiming.isPerfect(t: number, offset: number): boolean
	local _ = { t, offset }
	error("TODO(logic): PressTiming.isPerfect")
end

-- Instant du prochain sommet (anneau qui se resserre)
function PressTiming.nextApex(t: number, offset: number): number
	local _ = { t, offset }
	error("TODO(logic): PressTiming.nextApex")
end

-- tClient s'il est fini et dans [now − 0,35 ; now + 0,05], sinon now
function PressTiming.clampClientTime(tClient: number, now: number): number
	local _ = { tClient, now }
	error("TODO(logic): PressTiming.clampClientTime")
end

return PressTiming
