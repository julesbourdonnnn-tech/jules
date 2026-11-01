--!strict
-- MegaRules (paquet logic, docs/04 §12.1). MEGA SQUISH (GDD §4.22) : objectif adapté au nombre de
-- joueurs et indulgence après échec, paliers de bébés, fenêtre PERFECT du géant (décalée vers le
-- tard), espèce de la semaine en rotation.
-- Rebond du géant (même règle pour le serveur et le dessin du client) : période BouncePeriod (2 s)
-- à partir de l'atterrissage landsAt ; le géant touche le sol à landsAt + k × période et passe au
-- sommet à landsAt + (k + ½) × période. PERFECT = de PerfectBefore avant à PerfectAfter après un
-- sommet (Events.Mega).

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, math = type, math

local Events = require(script.Parent.Parent.Config.Events)
local Species = require(script.Parent.Parent.Config.Species)

local MegaRules = {}

local MEGA = Events.Mega
local MAX_PLAYERS = 1000 -- borne de sûreté (16 par serveur au lancement)
local EPSILON = 1e-9 -- tolérance d'arrondi aux bornes de la fenêtre PERFECT

local function finite(x: any, default: number): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return default
	end
	return x
end

-- ceil((30 + 50 × N) × indulgence)
function MegaRules.target(players: number, failStreak: number): number
	local n = math.clamp(math.floor(finite(players, 0)), 0, MAX_PLAYERS)
	return math.ceil((MEGA.TargetBase + MEGA.TargetPerPlayer * n) * MegaRules.leniency(failStreak))
end

-- 1 ; 0,8 après un échec ; 0,65 après 2 échecs de suite
function MegaRules.leniency(failStreak: number): number
	local list = MEGA.Leniency
	local fails = math.max(0, math.floor(finite(failStreak, 0)))
	return list[math.min(#list, fails + 1)]
end

-- Paliers : ≥ 10 → 1 ; ≥ 40 → 2 ; ≥ 80 → 3
function MegaRules.babiesFor(points: number): number
	local p = if type(points) == "number" and points == points then points else 0
	local babies = 0
	for _, tier in MEGA.Tiers do
		if p >= tier.points then
			babies = math.max(babies, tier.babies)
		end
	end
	return babies
end

-- Phase du rebond dans [0 ; 1[ (0 = au sol, 0,5 = sommet) ; 0 avant l'atterrissage
function MegaRules.phase(landsAt: number, t: number): number
	local l, tt = finite(landsAt, 0), finite(t, 0)
	local d = tt - l
	if not (d >= 0 and d < math.huge) then
		return 0 -- avant l'atterrissage, ou écart illisible
	end
	local p = (d % MEGA.BouncePeriod) / MEGA.BouncePeriod
	return if p >= 0 and p < 1 then p else 0
end

-- Instant du prochain sommet à partir de t (anneau qui se resserre côté client)
function MegaRules.nextApex(landsAt: number, t: number): number
	local l, tt = finite(landsAt, 0), finite(t, 0)
	local period = MEGA.BouncePeriod
	local first = l + period / 2
	if tt <= first then
		return first
	end
	local d = tt - first
	if not (d < math.huge) then
		return tt -- écart illisible : rien de mieux que maintenant
	end
	return math.max(tt, first + math.ceil(d / period) * period)
end

-- Fenêtre [−0,12 ; +0,28] s autour du sommet (période 2 s)
function MegaRules.isPerfect(landsAt: number, t: number): boolean
	if type(landsAt) ~= "number" or type(t) ~= "number" then
		return false
	end
	local l, tt = finite(landsAt, math.huge), finite(t, -math.huge)
	if l == math.huge or tt == -math.huge then
		return false
	end
	local period = MEGA.BouncePeriod
	local first = l + period / 2
	if tt < first - MEGA.PerfectBefore - EPSILON then
		return false -- avant le premier sommet
	end
	local offset = (tt - first) % period -- temps depuis le dernier sommet, dans [0 ; période[
	return offset <= MEGA.PerfectAfter + EPSILON or offset >= period - MEGA.PerfectBefore - EPSILON
end

-- ((semaine + n) mod 24) + 1, Secrets exclus
function MegaRules.species(week: number, indexInWeek: number): number
	-- bornes de sûreté : un modulo sur des doubles énormes n'est plus exact
	local w = math.clamp(math.floor(finite(week, 0)), -1e9, 1e9)
	local n = math.clamp(math.floor(finite(indexInWeek, 0)), -1e9, 1e9)
	local rotation = Species.MegaRotation
	return ((w + n) % rotation) + 1
end

return MegaRules
