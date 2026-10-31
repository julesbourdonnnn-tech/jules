--!strict
-- Formulas — paquet « logic » (docs/04-architecture.md §12.1).
-- Toutes les formules d'économie et de règles chiffrées, PURES (aucun service Roblox) et lues
-- dans Config/Balance, Config/Nebbies, Config/Cosmetics et Config/Quests. Les services n'écrivent
-- JAMAIS ces formules eux-mêmes. Invariants : jamais négatif, jamais NaN, monnaies = floor ;
-- une entrée invalide (NaN, ±inf, négatif, piste inconnue) donne une valeur sûre, jamais une erreur.
--   * améliorations : coût floor(Base × Growth^L) (Conga : 1,55 jusqu'au niveau 12 puis 1,20),
--     niveau max (Conga : min(12 + 5 R, 57))
--   * file : capacité min(3 + niveau, 60), Conga Bonus min(5, 1 + 0,08 (n − 1)) (Zen : ≤ 2,5),
--     Guard Links 3 + niveau (≤ 8), rayon d'Attrait 5 + 0,5 × niveau (× 1,5 en Snip Rush)
--   * vitesse : (16 + 0,5 × Foulée) × ralenti × comète + Dash + Second Souffle
--   * Dash : recharge max(5, 7 − 0,25 R)
--   * valeurs : parade = valeurParade × forme × variantes ; passif = passif × forme × variantes × ★
--   * M = (1 + 0,4 R + 0,25 VIP + 0,1 min(3, équipiers)) × (Double Glow ? 2) × (boost ? 2)
--   * parade : floor(Σ valeur × Bonus × M × (Balise ? 1,5)) ; hors ligne ; règlement paresseux
--   * Supernova : Balance.Supernova.Costs[R + 1] puis BeyondBase × BeyondGrowth^(R − BeyondFrom)
--   * perchoirs 3 + niveau + jalons d'Atlas + 6 (pass) ≤ 46 ; réserve 300/600
--   * Starforge (coûts), libération (Stardust × 3^(★−1)), capScale, plafonds effectifs,
--     objectif de la Balise (miséricorde), nombre de Gloomwisps, « X secondes de revenu passif »
-- GDD : §4.1-§4.18, §12.9 (Formulas.spec : tables de coûts du §4.11 au Glow près).

local Config = script.Parent.Parent.Config
local Balance = require(Config.Balance)
local Cosmetics = require(Config.Cosmetics)
local Nebbies = require(Config.Nebbies)
local Quests = require(Config.Quests)
local Types = require(script.Parent.Parent.Types)

local Formulas = {}

export type WalkSpeedParams = {
	stride: number, -- niveau de Foulée
	n: number, -- Nebbies dans la file
	guard: number, -- Guard Links (nombre, pas niveau)
	carrier: boolean, -- porteur de la Comète
	dashing: boolean, -- Dash en cours (ignoré si carrier)
	secondWind: boolean,
}

export type MultiplierParams = {
	supernovas: number,
	vip: boolean,
	crewPresent: number, -- équipiers présents et actifs
	doubleGlow: boolean,
	boost: boolean, -- boost personnel OU de serveur
}

export type SettleResult = {
	glow: number, -- nouveau solde
	carry: number, -- nouvelle fraction ∈ [0, 1[
	credited: number, -- Glow entier crédité
}

-- ---------------------------------------------------------------------------------------------
-- Aides internes : nombres sûrs
-- ---------------------------------------------------------------------------------------------

local HUGE = math.huge

-- Nombre fini, sinon `default`
local function finite(x: any, default: number): number
	if type(x) ~= "number" or x ~= x or x == HUGE or x == -HUGE then
		return default
	end
	return x
end

-- Entier ≥ 0 (niveaux, compteurs) : NaN/inf → 0, réels tronqués
local function level(x: any): number
	local v = finite(x, 0)
	if v <= 0 then
		return 0
	end
	return math.floor(v)
end

-- Monnaie : entier ≥ 0, jamais NaN ni inf (un débordement reste un grand entier fini)
local function money(x: number): number
	if x ~= x or x <= 0 then
		return 0
	end
	if x == HUGE then
		return 2 ^ 53
	end
	return math.floor(x)
end

-- ---------------------------------------------------------------------------------------------
-- Améliorations (§4.11)
-- ---------------------------------------------------------------------------------------------

-- Coût du niveau `level` (le premier achat se fait au niveau 0). Piste inconnue → math.huge
-- (achat impossible).
function Formulas.upgradeCost(track: Types.UpgradeTrack, lvl: number): number
	local def = Balance.Upgrades[track]
	if def == nil then
		return HUGE
	end
	local L = level(lvl)
	local raw
	local brk, after = def.Break, def.GrowthAfter
	if brk ~= nil and after ~= nil then
		raw = def.Base * def.Growth ^ math.min(L, brk) * after ^ math.max(0, L - brk)
	else
		raw = def.Base * def.Growth ^ L
	end
	return money(raw)
end

function Formulas.upgradeMaxLevel(track: Types.UpgradeTrack, supernovas: number): number
	local def = Balance.Upgrades[track]
	if def == nil then
		return 0
	end
	local maxBase, maxAbsolute = def.MaxBase, def.MaxAbsolute
	if maxBase ~= nil then
		local R = level(supernovas)
		local maxLevel = maxBase + (def.MaxPerSupernova or 0) * R
		if maxAbsolute ~= nil then
			maxLevel = math.min(maxLevel, maxAbsolute)
		end
		return maxLevel
	end
	return def.Max or 0
end

-- ---------------------------------------------------------------------------------------------
-- File, capture, vitesse (§4.5, §4.6, §4.7)
-- ---------------------------------------------------------------------------------------------

function Formulas.congaCapacity(congaLevel: number): number
	return math.min(Balance.Conga.BaseCapacity + level(congaLevel), Balance.Conga.AbsoluteMax)
end

function Formulas.congaBonus(n: number, zen: boolean?): number
	local count = level(n)
	local cap = if zen then Balance.Conga.ZenBonusMax else Balance.Conga.BonusMax
	if count <= 1 then
		return math.min(1, cap)
	end
	return math.min(cap, 1 + Balance.Conga.BonusStep * (count - 1))
end

function Formulas.guardLinks(guardLevel: number): number
	local g = Balance.Guard
	return math.min(g.Base + g.PerLevel * level(guardLevel), g.Max)
end

function Formulas.lureRadius(lureLevel: number, rush: boolean?): number
	local def = Balance.Upgrades.lure
	local L = math.min(level(lureLevel), if def and def.Max then def.Max else HUGE)
	local radius = Balance.Catch.LureBase + Balance.Catch.LurePerLevel * L
	if rush then
		radius *= Balance.Snip.RushLureMult
	end
	return radius
end

function Formulas.baseWalkSpeed(strideLevel: number): number
	local def = Balance.Upgrades.stride
	local L = math.min(level(strideLevel), if def and def.Max then def.Max else HUGE)
	return Balance.Speed.Base + Balance.Speed.PerStride * L
end

-- WalkSpeed serveur (§4.6) : base × ralenti × comète + Dash (sauf porteur) + Second Souffle
function Formulas.walkSpeed(p: WalkSpeedParams): number
	local base = Formulas.baseWalkSpeed(p.stride)
	local over = math.max(0, level(p.n) - level(p.guard))
	local slow = 1 - math.min(Balance.Conga.SlowMax, Balance.Conga.SlowPerNebby * over)
	local speed = base * slow
	if p.carrier then
		speed *= Balance.Speed.CarrierMult
	elseif p.dashing then
		speed += Balance.Dash.Boost
	end
	if p.secondWind then
		speed += Balance.Speed.SecondWindBoost
	end
	return speed
end

function Formulas.dashCooldown(supernovas: number): number
	local d = Balance.Dash
	return math.max(d.CooldownMin, d.CooldownBase - d.CooldownPerSupernova * level(supernovas))
end

-- ---------------------------------------------------------------------------------------------
-- Valeurs des Nebbies (§4.2, §4.4, §4.13)
-- ---------------------------------------------------------------------------------------------

-- Multiplicateur de forme × variantes (sans étoiles). Forme inconnue → ×1 ; bits inconnus ignorés.
function Formulas.nebbyMultiplier(f: number, v: number): number
	local form = Nebbies.Forms[level(f)]
	local mult = if form then form.mult else 1
	local bits = level(v) % 8
	if bits ~= 0 then
		for _, key in Nebbies.VARIANT_ORDER do
			local def = Nebbies.Variants[key]
			if def and bit32.btest(bits, def.bit) then
				mult *= def.mult
			end
		end
	end
	return mult
end

-- Valeur de parade d'un Nebby de file (★1). Code invalide → 0.
function Formulas.paradeValue(code: Types.NebbyCode): number
	if not Nebbies.isValidCode(code) then
		return 0
	end
	local s, f, v = Nebbies.unpack(code)
	local rarity = Nebbies.Rarities[Nebbies.rarityOf(s)]
	if rarity == nil then
		return 0
	end
	return rarity.parade * Formulas.nebbyMultiplier(f, v)
end

-- Revenu passif (Glow/s, sans M) d'un Nebby de la collection. Enregistrement invalide → 0.
function Formulas.passiveIncome(rec: Types.NebbyRecord): number
	if type(rec) ~= "table" then
		return 0
	end
	local s = finite(rec.s, 0)
	local def = Nebbies.Species[s]
	if def == nil then
		return 0
	end
	local rarity = Nebbies.Rarities[def.rarity]
	if rarity == nil then
		return 0
	end
	local stars = math.clamp(level(rec.st), 1, Nebbies.MAX_STARS)
	return rarity.passive
		* Formulas.nebbyMultiplier(finite(rec.f, 0), finite(rec.v, 0))
		* Nebbies.Stars[stars]
end

-- ---------------------------------------------------------------------------------------------
-- Multiplicateur global M et gains (§4.8, §4.9, §4.10)
-- ---------------------------------------------------------------------------------------------

function Formulas.multiplier(p: MultiplierParams): number
	local m = Balance.Multiplier
	local crew = math.min(m.MaxCrewMates, level(p.crewPresent))
	local additive = 1
		+ m.PerSupernova * level(p.supernovas)
		+ (if p.vip then m.VIP else 0)
		+ m.PerCrewMate * crew
	if p.doubleGlow then
		additive *= m.DoubleGlow
	end
	if p.boost then
		additive *= m.Boost
	end
	return additive
end

-- M hors ligne : sans boosts temporaires ni équipage (§4.9)
function Formulas.offlineMultiplier(supernovas: number, vip: boolean, doubleGlow: boolean): number
	return Formulas.multiplier({
		supernovas = supernovas,
		vip = vip,
		crewPresent = 0,
		doubleGlow = doubleGlow,
		boost = false,
	})
end

-- Glow d'une parade (floor) : Σ valeur × Conga Bonus × M × (Balise ? 1,5)
function Formulas.paradeGlow(codes: { Types.NebbyCode }, M: number, zen: boolean, atBeacon: boolean): number
	if type(codes) ~= "table" then
		return 0
	end
	local sum = 0
	local n = 0
	for _, code in ipairs(codes) do
		local value = Formulas.paradeValue(code)
		if value > 0 then
			sum += value
		end
		n += 1
	end
	if n == 0 then
		return 0
	end
	local mult = finite(M, 0)
	if mult <= 0 then
		return 0
	end
	local glow = sum * Formulas.congaBonus(n, zen) * mult
	if atBeacon then
		glow *= Balance.Parade.BeaconMult
	end
	return money(glow)
end

-- (Glow gagné, secondes retenues) hors ligne : durée bornée à [0, plafond], gain au taux réduit.
-- `rate` = revenu passif hors ligne (perchIncome × offlineMultiplier).
function Formulas.offlineGlow(rate: number, seconds: number, nightShift: boolean): (number, number)
	local o = Balance.Offline
	local cap = if nightShift then o.NightShiftCap else o.Cap
	local ratio = if nightShift then o.NightShiftRate else o.Rate
	local s = finite(seconds, 0)
	s = math.clamp(s, 0, cap)
	local r = math.max(0, finite(rate, 0))
	return money(r * s * ratio), s
end

-- Règlement paresseux : crédite floor(rate × dt + carry), garde la fraction
function Formulas.settle(glow: number, carry: number, rate: number, dt: number): SettleResult
	local g = money(finite(glow, 0))
	local c = finite(carry, 0)
	if c < 0 or c >= 1 then
		c = 0
	end
	local r = math.max(0, finite(rate, 0))
	local d = math.max(0, finite(dt, 0))
	local total = r * d + c
	local credited = money(total)
	local newCarry = total - credited
	if newCarry ~= newCarry or newCarry < 0 or newCarry >= 1 then
		newCarry = 0
	end
	return { glow = g + credited, carry = newCarry, credited = credited }
end

-- Glow = `seconds` de revenu passif (au moins `minGlow`)
function Formulas.glowForSeconds(rate: number, seconds: number, minGlow: number?): number
	local r = math.max(0, finite(rate, 0))
	local s = math.max(0, finite(seconds, 0))
	return math.max(money(finite(minGlow, 0)), money(r * s))
end

-- ---------------------------------------------------------------------------------------------
-- Supernova (§4.12)
-- ---------------------------------------------------------------------------------------------

function Formulas.supernovaCost(supernovas: number): number
	local sn = Balance.Supernova
	local R = level(supernovas)
	local cost = sn.Costs[R + 1]
	if cost ~= nil then
		return cost
	end
	return money(sn.BeyondBase * sn.BeyondGrowth ^ (R - sn.BeyondFrom))
end

-- Aura de file débloquée à R (Cosmetics.Auras : la plus haute atteinte), sinon nil
function Formulas.auraFor(supernovas: number): string?
	local R = level(supernovas)
	local best: string? = nil
	local bestAt = -1
	for key, def in Cosmetics.Auras do
		if def.supernovas <= R and def.supernovas > bestAt then
			best = key
			bestAt = def.supernovas
		end
	end
	return best
end

-- ---------------------------------------------------------------------------------------------
-- Perchoirs, réserve, Starforge, libération (§4.9, §4.13, §4.14)
-- ---------------------------------------------------------------------------------------------

-- Nombre de perchoirs gagnés par les jalons d'Atlas atteints pour `entries` entrées (≤ 10)
function Formulas.atlasPerchMilestones(entries: number): number
	local n = level(entries)
	local total = 0
	for _, milestone in Quests.Atlas.Milestones do
		local perch = milestone.perch
		if perch ~= nil and milestone.entries <= n then
			total += perch
		end
	end
	return math.min(total, Balance.Perches.AtlasMilestoneMax)
end

function Formulas.perchCount(perchLevel: number, atlasEntries: number, extraPerches: boolean): number
	local p = Balance.Perches
	local def = Balance.Upgrades.perches
	local L = math.min(level(perchLevel), if def and def.Max then def.Max else HUGE)
	local count = p.Base + p.PerLevel * L + Formulas.atlasPerchMilestones(atlasEntries)
	if extraPerches then
		count += p.ExtraPerchesPass
	end
	return math.min(count, p.Max)
end

function Formulas.stashCap(stashPlus: boolean): number
	return if stashPlus then Balance.Stash.Plus else Balance.Stash.Base
end

-- Coût en Stardust de ★stars → ★stars+1 (nil si ★5 ou nombre d'étoiles invalide)
function Formulas.fuseCost(stars: number): number?
	local st = finite(stars, 0)
	if st % 1 ~= 0 or st < 1 or st >= Balance.Starforge.MaxStars then
		return nil
	end
	return Balance.Starforge.Costs[st]
end

-- Stardust de la libération (nil si non libérable : Cosmique, rareté inconnue)
function Formulas.releaseDust(rarity: number, stars: number): number?
	local def = Nebbies.Rarities[level(rarity)]
	local dust = if def then def.dust else nil
	if dust == nil then
		return nil
	end
	local st = math.clamp(level(stars), 1, Nebbies.MAX_STARS)
	return money(dust * 3 ^ (st - 1))
end

-- ---------------------------------------------------------------------------------------------
-- Population, événements, protections (§4.3, §4.15, §4.16)
-- ---------------------------------------------------------------------------------------------

-- clamp((actifs + 4) / 16, 0,5, 1)
function Formulas.capScale(activePlayers: number): number
	local s = Balance.Spawn
	return math.clamp((level(activePlayers) + s.CapScaleOffset) / s.CapScaleDiv, s.CapScaleMin, s.CapScaleMax)
end

-- round(plafond × capScale × capMult), jamais négatif
function Formulas.effectiveCap(baseCap: number, activePlayers: number, capMult: number): number
	local base = math.max(0, finite(baseCap, 0))
	local mult = math.max(0, finite(capMult, 1))
	return math.floor(base * Formulas.capScale(activePlayers) * mult + 0.5)
end

-- Objectif de la Nuit de la Balise : max(20, 10 × actifs) × miséricorde (0,75 après 2 échecs
-- consécutifs, 0,5 après 3 et plus), arrondi à l'entier inférieur, au moins 1
function Formulas.beaconGoal(activePlayers: number, consecutiveFails: number): number
	local b = Balance.Beacon
	local fails = level(consecutiveFails)
	local mercy = if fails >= 3 then b.MercyAfter3 elseif fails >= 2 then b.MercyAfter2 else 1
	local goal = math.max(b.MinGoal, b.PerPlayer * level(activePlayers)) * mercy
	return math.max(1, math.floor(goal))
end

-- max(0, 5 − floor(actifs / 3)) ; 0 pendant la Balise ou Starfall (`suppressed`)
function Formulas.wispCount(activePlayers: number, suppressed: boolean): number
	if suppressed then
		return 0
	end
	local w = Balance.Wisps
	return math.max(0, w.Base - math.floor(level(activePlayers) / w.PlayersPerStep))
end

-- Bouclier débutant actif ? (session == 1 ou (temps cumulé < 30 min et R == 0))
function Formulas.rookieEligible(sessions: number, playSeconds: number, supernovas: number): boolean
	if level(sessions) <= 1 then
		return true
	end
	local played = math.max(0, finite(playSeconds, HUGE))
	return played < Balance.Rookie.PlayMinutes * 60 and level(supernovas) == 0
end

return Formulas
