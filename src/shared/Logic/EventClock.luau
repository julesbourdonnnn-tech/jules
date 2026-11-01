--!strict
-- EventClock (paquet logic, docs/04 §4, §12.1). Phases de chaque événement à l'instant t (UTC, en
-- secondes, Clock.now()), pures et identiques serveur / client (GDD §2.4, §12.4) :
--   Golden Wobbler (:00:30, :10:30, :30:30, :40:30, 30 s) ; BOOP RUSH (:05, :15… 90 s, sirène 10 s
--   avant) ; MEGA SQUISH (:20 et :50, alerte 15 s, 60 s de pression + 5 s d'éclatement) ; Jelly Moon
--   (samedi 16/18/20/22 h, dimanche 16 h, 20 min ; le MEGA de :20 qui suit une séance est un MEGA
--   MOON SQUISH). Tout vient de Config/Events.
-- Chaque phase rend l'occurrence EN COURS, sinon la PROCHAINE ; `index` est le numéro global de
-- l'occurrence depuis l'époque (graine et clé d'idempotence : un Rush n'est traité qu'une fois).
-- Un seul grand spectacle fixe à la fois, ≥ 20 s d'écart (vérifié sur 100 000 créneaux par
-- EventClock.spec). Semaine : lundi 00:00 UTC (même règle que Util/Clock.week).
-- Toute entrée bizarre (NaN, ±inf) est lue comme t = 0 : jamais d'erreur.

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, math, table = type, math, table

local Types = require(script.Parent.Parent.Types)
local Events = require(script.Parent.Parent.Config.Events)
local Hash = require(script.Parent.Hash)
local MegaRules = require(script.Parent.MegaRules)

local EventClock = {}

local HOUR = 3600
local DAY = 86400
local WEEK = 604800
local WEEK_EPOCH = 345600 -- lundi 05/01/1970 00:00 UTC (Util/Clock)
local SEED_SALT = 0xE7C10C -- sel des graines d'événement (figé)

local RUSH = Events.Rush
local MEGA = Events.Mega
local GOLDEN = Events.Golden
local MOON = Events.Moon

local function sane(t: any): number
	if type(t) ~= "number" or t ~= t or t == math.huge or t == -math.huge then
		return 0
	end
	return t
end

-- =============================================================================================
-- BOOP RUSH
-- =============================================================================================

local function rushAt(index: number): Types.RushPhase
	local startsAt = RUSH.Offset + index * RUSH.Period
	return {
		active = false,
		index = index,
		sirenAt = startsAt - RUSH.Siren,
		startsAt = startsAt,
		endsAt = startsAt + RUSH.Duration,
	}
end

-- Rush en cours ou prochain (index = numéro global du créneau)
function EventClock.rush(t: number): Types.RushPhase
	local tt = sane(t)
	local index = math.floor((tt - RUSH.Offset) / RUSH.Period)
	local phase = rushAt(index)
	if tt >= phase.endsAt then
		phase = rushAt(index + 1)
	end
	phase.active = tt >= phase.startsAt and tt < phase.endsAt
	return phase
end

-- =============================================================================================
-- Jelly Moon
-- =============================================================================================

-- Heures de début des séances dans la semaine (secondes depuis lundi 00:00), dans l'ordre
local MOON_STARTS: { number } = {}
for _, hour in MOON.Saturday do
	table.insert(MOON_STARTS, 5 * DAY + hour * HOUR) -- samedi = lundi + 5 jours
end
for _, hour in MOON.Sunday do
	table.insert(MOON_STARTS, 6 * DAY + hour * HOUR) -- dimanche = lundi + 6 jours
end
table.sort(MOON_STARTS)

local function weekStart(t: number): number
	return math.floor((t - WEEK_EPOCH) / WEEK) * WEEK + WEEK_EPOCH
end

-- Séance de Jelly Moon en cours ou prochaine (session 1-5 dans la semaine)
function EventClock.moon(t: number): Types.MoonPhase
	local tt = sane(t)
	local base = weekStart(tt)
	for weekShift = 0, 1 do
		local w = base + weekShift * WEEK
		for i, offset in MOON_STARTS do
			local startsAt = w + offset
			local endsAt = startsAt + MOON.Duration
			if tt < endsAt then
				return {
					active = tt >= startsAt,
					session = i,
					startsAt = startsAt,
					endsAt = endsAt,
				}
			end
		end
	end
	-- inaccessible (une semaine contient toujours une séance) : repli sûr
	return {
		active = false,
		session = 1,
		startsAt = base + WEEK + MOON_STARTS[1],
		endsAt = base + WEEK + MOON_STARTS[1] + MOON.Duration,
	}
end

-- =============================================================================================
-- MEGA SQUISH
-- =============================================================================================

local function megaAt(index: number): Types.MegaPhase
	local landsAt = MEGA.Offset + index * MEGA.Period
	local endsAt = landsAt + MEGA.PressTime
	return {
		active = false,
		index = index,
		warnAt = landsAt - MEGA.Warn,
		landsAt = landsAt,
		endsAt = endsAt,
		burstEndsAt = endsAt + MEGA.BurstTime,
		-- MEGA MOON SQUISH : une séance de Lune est en cours pendant l'alerte (le MEGA de :20 qui
		-- suit la séance de :00 à :20)
		moon = EventClock.moon(landsAt - MEGA.Warn).active,
	}
end

-- MEGA en cours ou prochain (moon = MEGA MOON SQUISH)
function EventClock.mega(t: number): Types.MegaPhase
	local tt = sane(t)
	local index = math.floor((tt - MEGA.Offset) / MEGA.Period)
	local phase = megaAt(index)
	if tt >= phase.burstEndsAt then
		phase = megaAt(index + 1)
	end
	phase.active = tt >= phase.landsAt and tt < phase.burstEndsAt
	return phase
end

-- =============================================================================================
-- Golden Wobbler
-- =============================================================================================

local GOLDEN_OFFSETS: { number } = table.clone(GOLDEN.Offsets)
table.sort(GOLDEN_OFFSETS)
local GOLDEN_PER_HOUR = #GOLDEN_OFFSETS

-- Golden Wobbler en cours ou prochain
function EventClock.golden(t: number): Types.GoldenPhase
	local tt = sane(t)
	local hour = math.floor(tt / HOUR)
	for hourShift = 0, 1 do
		local h = hour + hourShift
		for i, offset in GOLDEN_OFFSETS do
			local spawnAt = h * HOUR + offset
			local endsAt = spawnAt + GOLDEN.Duration
			if tt < endsAt then
				return {
					active = tt >= spawnAt,
					index = h * GOLDEN_PER_HOUR + (i - 1),
					spawnAt = spawnAt,
					endsAt = endsAt,
				}
			end
		end
	end
	local h = hour + 2
	return {
		active = false,
		index = h * GOLDEN_PER_HOUR,
		spawnAt = h * HOUR + GOLDEN_OFFSETS[1],
		endsAt = h * HOUR + GOLDEN_OFFSETS[1] + GOLDEN.Duration,
	}
end

-- =============================================================================================
-- Pastille du HUD, Lune et Rush, espèce du géant, graines, costumes
-- =============================================================================================

-- Prochain départ STRICTEMENT après t de chaque sorte (une occurrence en cours donne la suivante)
local function nextStarts(tt: number): { [string]: number }
	local rush = EventClock.rush(tt)
	local rushAtT = if rush.startsAt > tt then rush.startsAt else rush.startsAt + RUSH.Period
	local mega = EventClock.mega(tt)
	local megaAtT = if mega.landsAt > tt then mega.landsAt else mega.landsAt + MEGA.Period
	local golden = EventClock.golden(tt)
	local goldenAtT = golden.spawnAt
	if goldenAtT <= tt then
		goldenAtT = EventClock.golden(golden.endsAt).spawnAt
	end
	local moon = EventClock.moon(tt)
	local moonAtT = moon.startsAt
	if moonAtT <= tt then
		moonAtT = EventClock.moon(moon.endsAt).startsAt
	end
	return { rush = rushAtT, mega = megaAtT, golden = goldenAtT, moon = moonAtT }
end

-- Ordre en cas d'égalité (le plus grand spectacle d'abord)
local KIND_ORDER = { "moon", "mega", "rush", "golden" }

-- Prochain événement parmi les sortes permises (kinds[sorte] == true) ; nil si aucune. Fonction
-- ajoutée : la pastille du HUD n'annonce que les événements dont l'interrupteur du serveur est vrai
-- (EventState.features).
function EventClock.nextEventOf(t: number, kinds: { [string]: boolean }): Types.NextEvent?
	local tt = sane(t)
	local starts = nextStarts(tt)
	local best: Types.NextEvent? = nil
	for _, kind in KIND_ORDER do
		if type(kinds) == "table" and kinds[kind] == true then
			local at = starts[kind]
			if best == nil or at < best.at then
				best = { kind = kind :: any, at = at }
			end
		end
	end
	return best
end

-- Prochain événement pour la pastille du HUD
function EventClock.nextEvent(t: number): Types.NextEvent
	local all = { rush = true, mega = true, golden = true, moon = true }
	local event = EventClock.nextEventOf(t, all)
	if event then
		return event
	end
	return { kind = "rush", at = EventClock.rush(t).startsAt } -- inaccessible : repli sûr
end

-- Rush de :05 ou :15 pendant une séance de Lune (Mythiques et Secrets boopables). Évalué pour le Rush
-- en cours, sinon le prochain.
function EventClock.rushMoonBoopable(t: number): boolean
	local rush = EventClock.rush(sane(t))
	local minute = math.floor((rush.startsAt % HOUR) / 60)
	if not table.find(MOON.BoopableRushes, minute) then
		return false
	end
	return EventClock.moon(rush.startsAt).active
end

-- Espèce du géant (rotation du GDD §5.1, contrat v1.2) : MegaRules.species(semaine, numéro du MEGA
-- dans la semaine, atterrissage) sur les espèces publiées et non secrètes À L'ATTERRISSAGE (la même
-- pendant l'alerte et tout le MEGA, même si une espèce sort entre-temps), jamais mod 24
function EventClock.megaSpecies(t: number): number
	local mega = EventClock.mega(sane(t))
	local week = math.floor((mega.landsAt - WEEK_EPOCH) / WEEK)
	local start = week * WEEK + WEEK_EPOCH
	local indexInWeek = math.floor((mega.landsAt - start - MEGA.Offset) / MEGA.Period)
	if indexInWeek < 0 then
		indexInWeek = 0
	end
	return MegaRules.species(week, indexInWeek, mega.landsAt)
end

-- Graine des trajets d'un événement (Hash)
function EventClock.seed(kind: string, index: number): number
	local k = if type(kind) == "string" then kind else ""
	return Hash.u32(Hash.string(k), index, SEED_SALT)
end

-- Costume de saison actif (Events.Costumes), "" sinon
function EventClock.costume(unix: number): string
	local u = sane(unix)
	for _, costume in Events.Costumes do
		if u >= costume.from and u < costume.to then
			return costume.key
		end
	end
	return ""
end

return EventClock
