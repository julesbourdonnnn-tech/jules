--!strict
-- PressTiming (paquet logic, docs/04 §12.1). Phase du rebond et fenêtre PERFECT (GDD §4.7) :
-- période 1,2 s calée sur Clock.now() et un décalage propre au squishy (Hash du propriétaire et de
-- l'uid), donc identique côté client et serveur. Sommets à offset + k × période (phase 0).
-- Fenêtre de 0,08 s avant à 0,20 s après le sommet (retard des télés) ; tClient borné à
-- [maintenant − 0,35 ; maintenant + 0,05]. Tout vient de Balance.Press.

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, math = type, math

local Balance = require(script.Parent.Parent.Config.Balance)
local Hash = require(script.Parent.Hash)

local PressTiming = {}

local PRESS = Balance.Press
local OFFSET_SALT = 0x9E55 -- sel figé du décalage (changer = décaler tous les rebonds)
local EPSILON = 1e-9 -- tolérance d'arrondi aux bornes de la fenêtre PERFECT

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Décalage du rebond dans [0 ; Period[
function PressTiming.offset(ownerId: number, uid: string): number
	local key = if type(uid) == "string" then uid else ""
	return Hash.unit(ownerId, Hash.string(key), OFFSET_SALT) * PRESS.Period
end

-- Temps écoulé depuis le dernier sommet, dans [0 ; Period[
local function sinceApex(t: number, offset: number): number
	local tt = if finite(t) then t else 0
	local off = if finite(offset) then offset else 0
	local d = (tt - off) % PRESS.Period
	if d ~= d or d < 0 or d >= PRESS.Period then
		return 0
	end
	return d
end

-- Phase dans [0 ; 1[ (0 = sommet)
function PressTiming.phase(t: number, offset: number): number
	local p = sinceApex(t, offset) / PRESS.Period
	return if p >= 1 then 0 else p
end

-- t est dans la fenêtre PERFECT
function PressTiming.isPerfect(t: number, offset: number): boolean
	if not finite(t) then
		return false
	end
	local d = sinceApex(t, offset)
	return d <= PRESS.PerfectAfter + EPSILON or d >= PRESS.Period - PRESS.PerfectBefore - EPSILON
end

-- Instant du prochain sommet (anneau qui se resserre) : le premier sommet ≥ t
function PressTiming.nextApex(t: number, offset: number): number
	local tt = if finite(t) then t else 0
	local d = sinceApex(tt, offset)
	if d == 0 then
		return tt
	end
	return tt + (PRESS.Period - d)
end

-- tClient s'il est fini et dans [now − 0,35 ; now + 0,05], sinon now
function PressTiming.clampClientTime(tClient: number, now: number): number
	local n = if finite(now) then now else 0
	if finite(tClient) and tClient >= n - PRESS.ClientPast and tClient <= n + PRESS.ClientFuture then
		return tClient
	end
	return n
end

return PressTiming
