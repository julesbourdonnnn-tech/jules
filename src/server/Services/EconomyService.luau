--!strict
-- EconomyService — paquet « economy » (STUB du contrat : docs/04-architecture.md §11.5).
-- Propriétaire du Glow, de la Stardust, de R, des améliorations, des boosts et des plafonds du jour.
-- Responsabilités :
--   * accumulation PARESSEUSE : settle(player) crédite floor(idleRate × (now − lastSettle) + carry),
--     garde la fraction dans glowCarry ; appelé avant tout changement de taux ou de solde, toutes les
--     Idle.SettleInterval s (step, décalé par joueur) et avant chaque sauvegarde (DataService.onBeforeSave)
--   * idleRate = perchIncome (AtlasService) × M ; M (Formulas.multiplier) avec R, VIP, équipiers
--     présents (poussés par CrewService), Double Glow, boost personnel OU de serveur (poussé par
--     EventService) ; idleRate répliqué (clé de profil) pour la prédiction client ; Signals.RateChanged
--   * hors ligne au chargement : clamp(now − lastOnline, 0, plafond) × taux (50 %/8 h, Night Shift
--     75 %/12 h) × offlineRate (sans boosts ni équipage) ; écran de retour (Notify.celebrate
--     "offline") si ≥ 1 % du coût de la prochaine Supernova ou ≥ 1 000
--   * remote BuyUpgrade(track) : débit 10/s, piste valide, niveau < max, settle, coût → Signals.UpgradeBought,
--     Notify.celebrate "upgrade", Analytics (Upgrade_<piste>_<niveau>) ; refus : Feedback notEnoughGlow
--   * remote Supernova() : débit 1/2 s, dans son port sûr, encaissement de la file via le crochet
--     posé par CongaService (setLineBanker), settle, Glow ≥ coût → Glow, glowCarry, conga, stride,
--     lure remis à 0, supernovas + 1, Signals.Supernova, bannière, Celebrate, Analytics
--   * Stardust : add / trySpend / addCapped (plafonds du jour UTC : snipDust, wispDust, cheers, duo)
--   * boosts personnels (prolongés : personalUntil = max(now, personalUntil) + durée)
-- GDD : §4.1, §4.9-§4.12, §4.17, §7.2, §12.3 (settle), §12.6, §14.2.
-- Dépendances : DataService, MonetizationService, NestService, Logic/Formulas, Config/*, Signals,
-- Util/Notify, Util/RateLimit, Util/Analytics, Shared/Util/Clock.

local Types = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Types)

local EconomyService = {}

function EconomyService.Init() end

function EconomyService.Start() end

-- Règlements périodiques (appelé par le tick de CongaService à 10 Hz ; throttle interne)
function EconomyService.step(_now: number)
	error("TODO(economy): EconomyService.step")
end

-- Règle le revenu passif dû ; retourne le Glow crédité
function EconomyService.settle(_player: Player): number
	error("TODO(economy): EconomyService.settle")
end

-- Recalcule idleRate après un changement de M ou de perchIncome (settle d'abord !)
function EconomyService.refreshRate(_player: Player)
	error("TODO(economy): EconomyService.refreshRate")
end

function EconomyService.idleRate(_player: Player): number
	error("TODO(economy): EconomyService.idleRate")
end

function EconomyService.multiplier(_player: Player): number
	error("TODO(economy): EconomyService.multiplier")
end

-- Ajoute du Glow (floor, ≥ 0) ; retourne le montant crédité. sku : itemSku analytique (§14.2)
function EconomyService.addGlow(_player: Player, _amount: number, _sku: string, _txType: string?): number
	error("TODO(economy): EconomyService.addGlow")
end

-- Glow = `seconds` de revenu passif actuel (min `minGlow`) ; retourne le montant crédité
function EconomyService.addGlowSeconds(_player: Player, _seconds: number, _sku: string, _minGlow: number?): number
	error("TODO(economy): EconomyService.addGlowSeconds")
end

function EconomyService.trySpendGlow(_player: Player, _amount: number, _sku: string): boolean
	error("TODO(economy): EconomyService.trySpendGlow")
end

function EconomyService.addStardust(_player: Player, _amount: number, _sku: string, _txType: string?): number
	error("TODO(economy): EconomyService.addStardust")
end

-- Stardust soumise à un plafond du jour (capKey ∈ snipDust | wispDust | cheers | duo) ; retourne l'accordé
function EconomyService.addStardustCapped(_player: Player, _amount: number, _capKey: string, _sku: string): number
	error("TODO(economy): EconomyService.addStardustCapped")
end

function EconomyService.trySpendStardust(_player: Player, _amount: number, _sku: string): boolean
	error("TODO(economy): EconomyService.trySpendStardust")
end

-- Glow d'une parade (M au moment de la parade, Zen, Balise) — n'ajoute rien
function EconomyService.paradeGlow(_player: Player, _codes: { Types.NebbyCode }, _atBeacon: boolean): number
	error("TODO(economy): EconomyService.paradeGlow")
end

function EconomyService.upgradeLevel(_player: Player, _track: Types.UpgradeTrack): number
	error("TODO(economy): EconomyService.upgradeLevel")
end

function EconomyService.supernovas(_player: Player): number
	error("TODO(economy): EconomyService.supernovas")
end

function EconomyService.supernovaPreview(_player: Player): Types.SupernovaPreview
	error("TODO(economy): EconomyService.supernovaPreview")
end

function EconomyService.grantPersonalBoost(_player: Player, _seconds: number)
	error("TODO(economy): EconomyService.grantPersonalBoost")
end

function EconomyService.hasBoost(_player: Player): boolean
	error("TODO(economy): EconomyService.hasBoost")
end

-- Poussé par EventService : fin du boost ×2 de serveur (0 = aucun)
function EconomyService.setServerBoostUntil(_t: number)
	error("TODO(economy): EconomyService.setServerBoostUntil")
end

-- Poussé par CrewService : équipiers présents et actifs (bonus +10 % chacun, max 3)
function EconomyService.setCrewPresent(_player: Player, _count: number)
	error("TODO(economy): EconomyService.setCrewPresent")
end

-- Crochet posé par CongaService.Init : encaisse la file du joueur (parade forcée) avant une Supernova
function EconomyService.setLineBanker(_fn: (Player) -> ())
	error("TODO(economy): EconomyService.setLineBanker")
end

return EconomyService
