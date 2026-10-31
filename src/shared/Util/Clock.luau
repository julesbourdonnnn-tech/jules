--!strict
-- Clock : source de temps UNIQUE du jeu (serveur et client), docs/04-architecture.md §4.
-- Tous les services et contrôleurs lisent l'heure ici, jamais os.time() / os.clock() /
-- workspace:GetServerTimeNow() directement : les tests peuvent ainsi voyager dans le temps.
--
--   Clock.now()          secondes UTC fractionnaires, synchronisées serveur ↔ client
--                        (workspace:GetServerTimeNow(), identique des deux côtés)
--   Clock.unix()         floor(now()) : horodatages sauvegardés (lastOnline, boosts…)
--   Clock.day(t?)        jour UTC  = floor(t / 86400)
--   Clock.week(t?)       semaine   = floor((t − 345600) / 604800) (lundi 00:00 UTC)
--   Clock.weekday(t?)    0 = dimanche … 6 = samedi
--   Clock.secondOfDay(t?)
--
-- Tests : Clock.freeze(t), Clock.advance(dt), Clock.setOffset(s), Clock.unfreeze(), Clock.reset().
-- (Seules exceptions autorisées : RateLimit et les mesures de durée purement techniques.)

local Clock = {}

local DAY = 86400
local WEEK = 604800
local WEEK_EPOCH = 345600 -- lundi 05/01/1970 00:00 UTC
local WEEKDAY_OFFSET = 4 -- le 01/01/1970 était un jeudi

local offset = 0
local frozen: number? = nil

local function source(): number
	return workspace:GetServerTimeNow()
end

local function assertFinite(x: number, what: string)
	assert(
		type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge,
		`Clock.{what} : nombre fini attendu`
	)
end

function Clock.now(): number
	local f = frozen
	if f ~= nil then
		return f
	end
	return source() + offset
end

function Clock.unix(): number
	return math.floor(Clock.now())
end

function Clock.day(t: number?): number
	return math.floor((t or Clock.now()) / DAY)
end

function Clock.week(t: number?): number
	return math.floor(((t or Clock.now()) - WEEK_EPOCH) / WEEK)
end

function Clock.weekday(t: number?): number
	return (Clock.day(t) + WEEKDAY_OFFSET) % 7
end

function Clock.secondOfDay(t: number?): number
	local x = t or Clock.now()
	return x - math.floor(x / DAY) * DAY
end

-- Secondes restantes avant le prochain minuit UTC (remises à zéro quotidiennes)
function Clock.untilNextDay(t: number?): number
	local x = t or Clock.now()
	return (math.floor(x / DAY) + 1) * DAY - x
end

-- Secondes restantes avant le prochain lundi 00:00 UTC (remise à zéro hebdomadaire)
function Clock.untilNextWeek(t: number?): number
	local x = t or Clock.now()
	return (Clock.week(x) + 1) * WEEK + WEEK_EPOCH - x
end

-- ---------------------------------------------------------------------------------------------
-- Contrôle du temps (tests, outils de développement)
-- ---------------------------------------------------------------------------------------------

-- Décale l'horloge réelle de `seconds` (cumulable avec freeze)
function Clock.setOffset(seconds: number)
	assertFinite(seconds, "setOffset")
	offset = seconds
end

function Clock.getOffset(): number
	return offset
end

-- Fige le temps à `t` (par défaut : maintenant)
function Clock.freeze(t: number?)
	if t ~= nil then
		assertFinite(t, "freeze")
	end
	frozen = if t ~= nil then t else Clock.now()
end

-- Avance le temps de `dt` secondes (temps figé ou décalage)
function Clock.advance(dt: number)
	assertFinite(dt, "advance")
	local f = frozen
	if f ~= nil then
		frozen = f + dt
	else
		offset += dt
	end
end

function Clock.unfreeze()
	frozen = nil
end

function Clock.isFrozen(): boolean
	return frozen ~= nil
end

function Clock.reset()
	offset = 0
	frozen = nil
end

return Clock
