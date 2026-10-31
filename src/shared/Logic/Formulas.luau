--!strict
-- Formulas — paquet « logic » (STUB du contrat : docs/04-architecture.md §12.1).
-- Toutes les formules d'économie et de règles chiffrées, PURES (aucun service Roblox) et lues
-- dans Config/Balance, Config/Nebbies, Config/Monetization. Les services n'écrivent JAMAIS ces
-- formules eux-mêmes. Invariants : jamais négatif, jamais NaN, monnaies = floor.
-- Responsabilités :
--   * améliorations : coût floor(Base × Growth^L) (Conga : 1,55 jusqu'au niveau 12 puis 1,20),
--     niveau max (Conga : min(12 + 5 R, 57))
--   * file : capacité min(3 + niveau, 60), Conga Bonus min(5, 1 + 0,08 (n − 1)) (Zen : ≤ 2,5),
--     Guard Links 3 + niveau (≤ 8), rayon d'Attrait 5 + 0,5 × niveau (× 1,5 en Snip Rush)
--   * vitesse : (16 + 0,5 × Foulée) × ralenti × comète + Dash + Second Souffle
--   * Dash : recharge max(5, 7 − 0,25 R)
--   * valeurs : parade = valeurParade × forme × variantes ; passif = passif × forme × variantes × ★
--   * M = (1 + 0,4 R + 0,25 VIP + 0,1 min(3, équipiers)) × (Double Glow ? 2) × (boost ? 2)
--   * parade : floor(Σ valeur × Bonus × M × (Balise ? 1,5)) ; hors ligne ; règlement paresseux
--   * Supernova : Balance.Supernova.Costs[R + 1] puis 34e9 × 1,5^(R − 11)
--   * perchoirs 3 + niveau + jalons d'Atlas + 6 (pass) ≤ 46 ; réserve 300/600
--   * Starforge (coûts), libération (Stardust × 3^(★−1)), capScale, plafonds effectifs,
--     objectif de la Balise (miséricorde), nombre de Gloomwisps, « X secondes de revenu passif »
-- GDD : §4.1-§4.18, §12.9 (Formulas.spec : tables de coûts du §4.11 au Glow près).
-- Dépendances : Config/Balance, Config/Nebbies, Config/Monetization.

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

function Formulas.upgradeCost(_track: Types.UpgradeTrack, _level: number): number
	error("TODO(logic): Formulas.upgradeCost")
end

function Formulas.upgradeMaxLevel(_track: Types.UpgradeTrack, _supernovas: number): number
	error("TODO(logic): Formulas.upgradeMaxLevel")
end

function Formulas.congaCapacity(_congaLevel: number): number
	error("TODO(logic): Formulas.congaCapacity")
end

function Formulas.congaBonus(_n: number, _zen: boolean?): number
	error("TODO(logic): Formulas.congaBonus")
end

function Formulas.guardLinks(_guardLevel: number): number
	error("TODO(logic): Formulas.guardLinks")
end

function Formulas.lureRadius(_lureLevel: number, _rush: boolean?): number
	error("TODO(logic): Formulas.lureRadius")
end

function Formulas.baseWalkSpeed(_strideLevel: number): number
	error("TODO(logic): Formulas.baseWalkSpeed")
end

function Formulas.walkSpeed(_p: WalkSpeedParams): number
	error("TODO(logic): Formulas.walkSpeed")
end

function Formulas.dashCooldown(_supernovas: number): number
	error("TODO(logic): Formulas.dashCooldown")
end

-- Multiplicateur de forme × variantes (sans étoiles)
function Formulas.nebbyMultiplier(_f: number, _v: number): number
	error("TODO(logic): Formulas.nebbyMultiplier")
end

-- Valeur de parade d'un Nebby de file (★1)
function Formulas.paradeValue(_code: Types.NebbyCode): number
	error("TODO(logic): Formulas.paradeValue")
end

-- Revenu passif (Glow/s, sans M) d'un Nebby de la collection
function Formulas.passiveIncome(_rec: Types.NebbyRecord): number
	error("TODO(logic): Formulas.passiveIncome")
end

function Formulas.multiplier(_p: MultiplierParams): number
	error("TODO(logic): Formulas.multiplier")
end

-- M hors ligne : sans boosts temporaires ni équipage (§4.9)
function Formulas.offlineMultiplier(_supernovas: number, _vip: boolean, _doubleGlow: boolean): number
	error("TODO(logic): Formulas.offlineMultiplier")
end

-- Glow d'une parade (floor)
function Formulas.paradeGlow(_codes: { Types.NebbyCode }, _M: number, _zen: boolean, _atBeacon: boolean): number
	error("TODO(logic): Formulas.paradeGlow")
end

-- (Glow gagné, secondes retenues) hors ligne
function Formulas.offlineGlow(_rate: number, _seconds: number, _nightShift: boolean): (number, number)
	error("TODO(logic): Formulas.offlineGlow")
end

-- Règlement paresseux : crédite floor(rate × dt + carry)
function Formulas.settle(_glow: number, _carry: number, _rate: number, _dt: number): SettleResult
	error("TODO(logic): Formulas.settle")
end

-- Glow = `seconds` de revenu passif (au moins `minGlow`)
function Formulas.glowForSeconds(_rate: number, _seconds: number, _minGlow: number?): number
	error("TODO(logic): Formulas.glowForSeconds")
end

function Formulas.supernovaCost(_supernovas: number): number
	error("TODO(logic): Formulas.supernovaCost")
end

-- Aura de file débloquée à R (Cosmetics.Auras), sinon nil
function Formulas.auraFor(_supernovas: number): string?
	error("TODO(logic): Formulas.auraFor")
end

-- Nombre de jalons « +1 perchoir » atteints pour `entries` entrées d'Atlas (≤ 10)
function Formulas.atlasPerchMilestones(_entries: number): number
	error("TODO(logic): Formulas.atlasPerchMilestones")
end

function Formulas.perchCount(_perchLevel: number, _atlasEntries: number, _extraPerches: boolean): number
	error("TODO(logic): Formulas.perchCount")
end

function Formulas.stashCap(_stashPlus: boolean): number
	error("TODO(logic): Formulas.stashCap")
end

-- Coût en Stardust de ★stars → ★stars+1 (nil si ★5)
function Formulas.fuseCost(_stars: number): number?
	error("TODO(logic): Formulas.fuseCost")
end

-- Stardust de la libération (nil si non libérable : Cosmique)
function Formulas.releaseDust(_rarity: number, _stars: number): number?
	error("TODO(logic): Formulas.releaseDust")
end

function Formulas.capScale(_activePlayers: number): number
	error("TODO(logic): Formulas.capScale")
end

function Formulas.effectiveCap(_baseCap: number, _activePlayers: number, _capMult: number): number
	error("TODO(logic): Formulas.effectiveCap")
end

function Formulas.beaconGoal(_activePlayers: number, _consecutiveFails: number): number
	error("TODO(logic): Formulas.beaconGoal")
end

function Formulas.wispCount(_activePlayers: number, _suppressed: boolean): number
	error("TODO(logic): Formulas.wispCount")
end

-- Bouclier débutant actif ? (session == 1 ou (temps cumulé < 30 min et R == 0))
function Formulas.rookieEligible(_sessions: number, _playSeconds: number, _supernovas: number): boolean
	error("TODO(logic): Formulas.rookieEligible")
end

return Formulas
