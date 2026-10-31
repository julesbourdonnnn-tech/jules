--!strict
-- EconomyService — paquet « economy » (docs/04-architecture.md §11.5).
-- Propriétaire du Glow, de la Stardust, de R, des améliorations, des boosts et des plafonds du jour.
-- Clés de profil : glow, glowCarry, lastSettle, lastOnline, idleRate, stardust, supernovas, upgrades,
-- boosts, caps.
-- Responsabilités :
--   * accumulation PARESSEUSE : settle(player) crédite floor(idleRate × (now − lastSettle) + carry),
--     garde la fraction dans glowCarry ; appelé avant tout changement de taux ou de solde, toutes les
--     Idle.SettleInterval s (step, décalé par joueur) et avant chaque sauvegarde (DataService.onBeforeSave).
--     Une fin de boost est réglée À L'INSTANT de la fin (ancien taux), puis le taux est recalculé.
--   * idleRate = perchIncome (AtlasService) × M ; M (Formulas.multiplier) avec R, VIP, équipiers
--     présents (poussés par CrewService), Double Glow, boost personnel OU de serveur (poussé par
--     EventService) ; idleRate répliqué (clé de profil) pour la prédiction client ; Signals.RateChanged
--   * hors ligne au premier traitement du profil : Formulas.offlineGlow (50 %/8 h, Night Shift
--     75 %/12 h, sans boosts ni équipage) ; écran de retour (Notify.celebrate "offline") si ≥ 1 % du
--     coût de la prochaine Supernova ou ≥ 1 000 Glow ; premier chargement (lastOnline == 0) : rien.
--     La vérification des passes à l'arrivée (MonetizationService, UserOwnsGamePassAsync) peut finir
--     APRÈS ce calcul : au premier PassGranted d'un pass à effet hors ligne (offlineRate, glowBonus,
--     glowMult) dans les OFFLINE_PASS_WINDOW s, le gain est recalculé avec les passes possédés (achat
--     sur le site pendant l'absence) et la différence créditée une fois (Analytics « Offline »,
--     écran de retour mis à jour) ; un pass acheté EN JEU (PassPurchased) n'est jamais rétroactif
--   * attribut Player GuardLinks = Formulas.guardLinks(upgrades.guard) (rendu des files des autres
--     joueurs, docs §3.3) : au chargement, après chaque achat et après une Supernova
--   * invariants de développement (Economy/Invariants, Studio seulement) : avant chaque sauvegarde,
--     après BuyUpgrade et après une Supernova
--   * remote BuyUpgrade(track) : débit 10/s, piste valide, settle, niveau < max, coût →
--     Signals.UpgradeBought, Notify.celebrate "upgrade", Analytics Upgrade_<piste>_<niveau>
--   * remote Supernova() : débit 1/2 s, port sûr de son Nid (position de CONFIANCE : la dernière
--     validée par MoveCheck, jamais la seule position du client, voir NestService.inOwnHarbor), PUIS
--     encaissement de la file (crochet de CongaService), settle, Glow ≥ coût → Glow, glowCarry et
--     pistes ResetOnSupernova remis à 0,
--     supernovas + 1, Signals.Supernova, bannière, Celebrate, Analytics Supernova_<R>, SupernovaReached
--   * Stardust : add / trySpend / addCapped (plafonds du jour UTC : snipDust, wispDust en Stardust ;
--     cheers en nombre d'acclamations ; duo une fois par jour)
--   * boosts personnels prolongés (personalUntil = max(now, personalUntil) + durée, jamais ×4)
-- GDD : §4.1, §4.8-§4.12, §4.16 (Zen), §7.2, §12.3, §12.6, §14.2.
-- Dépendances : DataService, MonetizationService, NestService, Logic/Formulas, Config/*, Signals,
-- Util/Notify, Util/RateLimit, Util/Analytics, Shared/Util/Clock, Economy/{PassEffects,Invariants}.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Monetization = require(Shared.Config.Monetization)
local Formulas = require(Shared.Logic.Formulas)
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Clock = require(Shared.Util.Clock)
local Validate = require(Shared.Util.Validate)

local Server = script.Parent.Parent
local Signals = require(Server.Signals)
local Notify = require(Server.Util.Notify)
local RateLimit = require(Server.Util.RateLimit)
local Analytics = require(Server.Util.Analytics)
local PassEffects = require(Server.Economy.PassEffects)
local Invariants = require(Server.Economy.Invariants)
local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local NestService = require(script.Parent.NestService)

local EconomyService = {}

-- Plus grand entier exact d'un double : les soldes ne le dépassent jamais
local MAX_MONEY = 2 ^ 53

-- Plafonds du jour comptés en NOMBRE d'événements (et non en Stardust)
local COUNT_CAPS: { [string]: boolean } = { cheers = true }

-- Fenêtre (s, depuis le traitement du profil) pendant laquelle la vérification des passes à
-- l'arrivée peut encore compléter le gain hors ligne (UserOwnsGamePassAsync répond en quelques s)
local OFFLINE_PASS_WINDOW = 30

-- Champs d'effet de pass qui entrent dans le gain hors ligne (Config/Monetization.PassDef)
local OFFLINE_PASS_FIELDS = { "offlineRate", "glowBonus", "glowMult" }

-- Gain hors ligne crédité au chargement, gardé pour un complément éventuel (passes vérifiés après)
type OfflineContext = {
	startedAt: number, -- Clock.now() du traitement du profil
	away: number, -- secondes d'absence (Clock.unix() − lastOnline)
	perchIncome: number, -- revenu perché enregistré au chargement (base du calcul)
	R: number,
	credited: number, -- Glow hors ligne déjà crédité
	done: boolean, -- complément déjà évalué (une seule fois)
	purchased: { [string]: boolean }, -- passes achetés EN JEU pendant la fenêtre : jamais rétroactifs
}

-- État de session d'un profil, indexé par la TABLE du profil (faible) : il survit au nettoyage
-- par joueur tant que DataService garde le profil (crochet de sauvegarde au départ).
type Session = {
	boostEndsAt: number?, -- fin du boost ×2 pris en compte dans idleRate (nil = taux sans boost)
	nextSettleAt: number?, -- prochain règlement périodique (step)
	idleGlow: number, -- Glow passif cumulé pour l'événement analytique « Idle »
	idleSince: number,
	offline: OfflineContext?, -- gain hors ligne de cette session (nil : premier chargement, aucun revenu)
}

local sessions: { [any]: Session } = setmetatable({}, { __mode = "k" }) :: any
local crewPresent: { [Player]: number } = {}
local serverBoostUntil = 0
local lineBanker: ((Player) -> ())? = nil

-- ---------------------------------------------------------------------------------------------
-- Aides : nombres sûrs, profil
-- ---------------------------------------------------------------------------------------------

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Entier ≥ 0 borné (monnaies, niveaux) ; NaN/inf/non-nombre → 0
local function money(x: any): number
	if not finite(x) or x <= 0 then
		return 0
	end
	return math.min(math.floor(x), MAX_MONEY)
end

-- Type de transaction analytique d'après l'itemSku (§14.2), si l'appelant n'en donne pas
local function txTypeFor(sku: string): string
	if string.sub(sku, 1, 8) == "Product_" then
		return "IAP"
	elseif sku == "Offline" or sku == "Idle" or string.sub(sku, 1, 6) == "Login_" then
		return "TimedReward"
	elseif string.match(sku, "^Quest_q%d") then
		return "Onboarding"
	elseif string.sub(sku, 1, 8) == "Upgrade_" or string.sub(sku, 1, 10) == "Starforge_" then
		return "Shop"
	end
	return "Gameplay"
end

-- Répare les champs économiques d'un profil (anciennes sauvegardes, valeurs inattendues)
local function sanitize(data: { [string]: any })
	data.glow = money(data.glow)
	data.stardust = money(data.stardust)
	data.supernovas = money(data.supernovas)
	if not finite(data.glowCarry) or data.glowCarry < 0 or data.glowCarry >= 1 then
		data.glowCarry = 0
	end
	if not finite(data.lastOnline) or data.lastOnline < 0 then
		data.lastOnline = 0
	end
	if not finite(data.idleRate) or data.idleRate < 0 then
		data.idleRate = 0
	end
	if type(data.upgrades) ~= "table" then
		data.upgrades = {}
	end
	for _, track in Balance.UpgradeOrder do
		data.upgrades[track] = money(data.upgrades[track])
	end
	if type(data.boosts) ~= "table" then
		data.boosts = { personalUntil = 0 }
	end
	if not finite(data.boosts.personalUntil) then
		data.boosts.personalUntil = 0
	end
	if type(data.caps) ~= "table" then
		data.caps = { day = 0, snipDust = 0, wispDust = 0, cheers = 0, duo = false }
	end
end

-- Revenu passif des perchés SANS M (clé possédée par AtlasService : lue, jamais réparée ici)
local function perchIncome(data: { [string]: any }): number
	local income = data.perchIncome
	if not finite(income) or income < 0 then
		return 0
	end
	return income
end

local function boostActive(data: { [string]: any }, now: number): boolean
	return data.boosts.personalUntil > now or serverBoostUntil > now
end

local function multiplierAt(player: Player, data: { [string]: any }, now: number): number
	return Formulas.multiplier({
		supernovas = data.supernovas,
		vip = PassEffects.vip(player),
		crewPresent = crewPresent[player] or 0,
		doubleGlow = PassEffects.doubleGlow(player),
		boost = boostActive(data, now),
	})
end

-- Recalcule idleRate SANS régler (le règlement doit avoir eu lieu juste avant)
local function applyRate(player: Player, data: { [string]: any }, session: Session, now: number)
	local rate = perchIncome(data) * multiplierAt(player, data, now)
	if not finite(rate) or rate < 0 then
		rate = 0
	end
	if boostActive(data, now) then
		session.boostEndsAt = math.max(data.boosts.personalUntil, serverBoostUntil)
	else
		session.boostEndsAt = nil
	end
	if rate ~= data.idleRate then
		data.idleRate = rate
		DataService.markDirty(player, "idleRate")
		-- la prédiction client (glow + idleRate × (t − lastSettle)) dépend des deux clés
		DataService.markDirty(player, "lastSettle")
		Signals.RateChanged:Fire(player, rate)
	end
end

-- Crédite le revenu passif de lastSettle jusqu'à `t` au taux enregistré ; (crédité, secondes)
local function settleTo(player: Player, data: { [string]: any }, t: number): (number, number)
	local last = data.lastSettle
	if not finite(last) or last <= 0 or last > t then
		-- horodatage absent ou dans le futur : on repart de t sans rien créditer
		data.lastSettle = t
		return 0, 0
	end
	local dt = t - last
	if dt <= 0 then
		return 0, 0
	end
	local rate = data.idleRate
	local res = Formulas.settle(data.glow, data.glowCarry, rate, dt)
	local glow = math.min(res.glow, MAX_MONEY)
	local credited = glow - data.glow
	if credited < 0 then
		credited = 0
	end
	if glow ~= data.glow then
		data.glow = glow
		DataService.markDirty(player, "glow")
	end
	if res.carry ~= data.glowCarry then
		data.glowCarry = res.carry
		DataService.markDirty(player, "glowCarry")
	end
	data.lastSettle = t
	if rate > 0 then
		DataService.markDirty(player, "lastSettle")
		return credited, dt
	end
	return credited, 0
end

-- Règlement complet à l'instant `now` (fin de boost comprise) ; retourne le Glow crédité
local function settleCore(player: Player, data: { [string]: any }, session: Session, now: number): number
	local credited, seconds = 0, 0
	local endsAt = session.boostEndsAt
	if endsAt ~= nil and endsAt <= now then
		-- le boost a pris fin : l'ancien taux jusqu'à la fin, puis le nouveau taux
		if endsAt > data.lastSettle then
			local c, s = settleTo(player, data, endsAt)
			credited += c
			seconds += s
		end
		applyRate(player, data, session, endsAt)
	end
	local c, s = settleTo(player, data, now)
	credited += c
	seconds += s
	data.lastOnline = math.floor(now)
	if seconds > 0 then
		Signals.IdleSettled:Fire(player, credited, seconds)
	end
	-- analytique « Idle » cumulée par tranche de 5 min
	session.idleGlow += credited
	if now - session.idleSince >= Balance.Idle.AnalyticsEvery then
		if session.idleGlow > 0 then
			Analytics.earn(player, "Glow", session.idleGlow, data.glow, "TimedReward", "Idle")
		end
		session.idleGlow = 0
		session.idleSince = now
	end
	return credited
end

-- Attribut Player GuardLinks (maillons protégés de SA file, lu par le rendu des autres clients)
local function applyGuardLinks(player: Player, data: { [string]: any })
	if player.Parent == nil or type(data.upgrades) ~= "table" then
		return
	end
	player:SetAttribute("GuardLinks", Formulas.guardLinks(money(data.upgrades.guard)))
end

-- Le pass `passKey` agit-il sur le gain hors ligne ?
local function hasOfflineEffect(passKey: string): boolean
	for _, field in OFFLINE_PASS_FIELDS do
		if PassEffects.passHas(passKey, field) then
			return true
		end
	end
	return false
end

-- Le joueur possède-t-il un pass à l'effet `field`, sans compter les passes `except` ?
local function ownsEffectExcept(player: Player, field: string, except: { [string]: boolean }): boolean
	for passKey in Monetization.Passes do
		if not except[passKey] and PassEffects.passHas(passKey, field) then
			if MonetizationService.ownsPass(player, passKey) then
				return true
			end
		end
	end
	return false
end

-- Gain hors ligne de `away` s avec les passes possédés (sauf `except`) : (gain, secondes, Night Shift)
local function offlineGainFor(
	player: Player,
	income: number,
	R: number,
	away: number,
	except: { [string]: boolean }
): (number, number, boolean)
	local nightShift = ownsEffectExcept(player, "offlineRate", except)
	local M = Formulas.offlineMultiplier(
		R,
		ownsEffectExcept(player, "glowBonus", except),
		ownsEffectExcept(player, "glowMult", except)
	)
	local gain, seconds = Formulas.offlineGlow(income * M, away, nightShift)
	return gain, seconds, nightShift
end

-- Écran de retour si le gain le mérite (≥ 1 % du coût de la prochaine Supernova ou ≥ 1 000 Glow)
local function celebrateOffline(
	player: Player,
	R: number,
	glow: number,
	seconds: number,
	nightShift: boolean,
	away: number
)
	local o = Balance.Offline
	if glow >= o.ReturnMinRatio * Formulas.supernovaCost(R) or glow >= o.ReturnMinGlow then
		Notify.celebrate(player, "offline", {
			glow = glow,
			seconds = seconds,
			nightShift = nightShift,
			away = away,
		})
	end
end

-- Premier traitement d'un profil chargé : gains hors ligne, horloges, taux, écran de retour
local function processLoad(player: Player, data: { [string]: any }): Session
	local now = Clock.now()
	sanitize(data)
	local session: Session = { boostEndsAt = nil, nextSettleAt = nil, idleGlow = 0, idleSince = now }
	sessions[data] = session
	applyGuardLinks(player, data)

	local nowUnix = Clock.unix()
	local lastOnline = data.lastOnline
	if lastOnline > 0 then
		local R = data.supernovas
		local income = perchIncome(data)
		local away = math.max(0, nowUnix - lastOnline)
		local gain, seconds, nightShift = offlineGainFor(player, income, R, away, {})
		gain = math.min(gain, MAX_MONEY - data.glow)
		if gain > 0 then
			data.glow += gain
			DataService.markDirty(player, "glow")
			Analytics.earn(player, "Glow", gain, data.glow, "TimedReward", "Offline")
			celebrateOffline(player, R, gain, seconds, nightShift, away)
		end
		if income > 0 and away > 0 then
			session.offline = {
				startedAt = now,
				away = away,
				perchIncome = income,
				R = R,
				credited = math.max(gain, 0),
				done = false,
				purchased = {},
			}
		end
	end

	data.lastSettle = now
	data.lastOnline = nowUnix
	if data.idleRate > 0 then
		-- nouvelle session : la prédiction client repart de maintenant
		DataService.markDirty(player, "lastSettle")
	end
	applyRate(player, data, session, now)
	return session
end

-- Profil chargé et traité (gains hors ligne compris) ; nil si absent ou joueur parti
local function ensure(player: Player): ({ [string]: any }?, Session?)
	local data = DataService.get(player)
	if not data then
		return nil, nil
	end
	local session = sessions[data]
	if session then
		return data, session
	end
	if player.Parent == nil then
		return nil, nil
	end
	return data, processLoad(player, data)
end

-- Plafonds du jour remis à zéro au premier accès d'un nouveau jour UTC
local function capsFor(player: Player, data: { [string]: any }): { [string]: any }
	local caps = data.caps
	local today = Clock.day()
	if caps.day ~= today then
		caps.day = today
		for key, value in caps do
			if key ~= "day" then
				caps[key] = if type(value) == "boolean" then false else 0
			end
		end
		for key in Balance.DailyCaps do
			if caps[key] == nil then
				caps[key] = 0
			end
		end
		if caps.duo == nil then
			caps.duo = false
		end
		DataService.markDirty(player, "caps")
	end
	return caps
end

local function addGlowRaw(
	player: Player,
	data: { [string]: any },
	amount: number,
	sku: string,
	txType: string?
): number
	local credited = math.min(money(amount), MAX_MONEY - data.glow)
	if credited <= 0 then
		return 0
	end
	data.glow += credited
	DataService.markDirty(player, "glow")
	Analytics.earn(player, "Glow", credited, data.glow, txType or txTypeFor(sku), sku)
	return credited
end

local function addStardustRaw(
	player: Player,
	data: { [string]: any },
	amount: number,
	sku: string,
	txType: string?
): number
	local credited = math.min(money(amount), MAX_MONEY - data.stardust)
	if credited <= 0 then
		return 0
	end
	data.stardust += credited
	DataService.markDirty(player, "stardust")
	Analytics.earn(player, "Stardust", credited, data.stardust, txType or txTypeFor(sku), sku)
	return credited
end

-- Complément hors ligne (passes confirmés par la vérification d'arrivée APRÈS le calcul du
-- chargement : achat sur le site pendant l'absence). Une seule évaluation par session, dans la
-- fenêtre OFFLINE_PASS_WINDOW ; jamais de retrait (gain recalculé plus faible : rien ne change).
local function topUpOffline(player: Player, passKey: string)
	local data = DataService.get(player)
	local session = if data then sessions[data] else nil
	local ctx = if session then session.offline else nil
	if data == nil or ctx == nil or ctx.done or player.Parent == nil then
		return
	end
	if ctx.purchased[passKey] then
		return -- acheté en jeu à l'instant : pas rétroactif (la vérification d'arrivée peut suivre)
	end
	ctx.done = true
	if Clock.now() - ctx.startedAt > OFFLINE_PASS_WINDOW then
		return
	end
	local gain, seconds, nightShift = offlineGainFor(player, ctx.perchIncome, ctx.R, ctx.away, ctx.purchased)
	local extra = gain - ctx.credited
	if extra <= 0 then
		return
	end
	local credited = addGlowRaw(player, data, extra, "Offline", "TimedReward")
	if credited <= 0 then
		return
	end
	ctx.credited += credited
	celebrateOffline(player, ctx.R, ctx.credited, seconds, nightShift, ctx.away)
end

-- ---------------------------------------------------------------------------------------------
-- Cycle de vie
-- ---------------------------------------------------------------------------------------------

function EconomyService.Init()
	-- règle le revenu passif juste avant chaque écriture (autosave, achat, départ, fermeture)
	DataService.onBeforeSave(function(player: Player, data: { [string]: any })
		local session = sessions[data]
		if session then
			settleCore(player, data, session, Clock.now())
		end
	end)
end

function EconomyService.Start()
	DataService.Loaded:Connect(function(player: Player)
		ensure(player)
	end)
	-- invariants de développement (Studio) juste avant chaque écriture, après le règlement (Init)
	DataService.onBeforeSave(function(player: Player, data: { [string]: any })
		if sessions[data] then
			Invariants.check(player, data, "sauvegarde")
		end
	end)
	-- passes vérifiés à l'arrivée après le calcul hors ligne : complément éventuel. Différé : un
	-- achat EN JEU émet PassPurchased juste après PassGranted (même fil) et n'est pas rétroactif.
	MonetizationService.PassGranted:Connect(function(player: Player, passKey: string)
		if hasOfflineEffect(passKey) then
			task.defer(topUpOffline, player, passKey)
		end
	end)
	MonetizationService.PassPurchased:Connect(function(player: Player, passKey: string)
		local data = DataService.get(player)
		local session = if data then sessions[data] else nil
		local ctx = if session then session.offline else nil
		if ctx then
			ctx.purchased[passKey] = true
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		crewPresent[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		if DataService.isLoaded(player) then
			task.spawn(ensure, player)
		end
	end

	Net.event("BuyUpgrade").OnServerEvent:Connect(function(player: Player, track: unknown)
		if not RateLimit.allow(player, "BuyUpgrade", 10, 1) then
			return
		end
		if not Validate.key(track, Balance.Upgrades, 16) then
			return
		end
		EconomyService.buyUpgrade(player, track :: Types.UpgradeTrack)
	end)

	Net.event("Supernova").OnServerEvent:Connect(function(player: Player)
		if not RateLimit.allow(player, "Supernova", 1, 2) then
			return
		end
		EconomyService.trySupernova(player)
	end)
end

-- Règlements périodiques (tick de CongaService, 10 Hz) : chaque joueur toutes les
-- Idle.SettleInterval s, décalé selon son index ; fins de boost réglées à l'instant exact
function EconomyService.step(now: number)
	local players = Players:GetPlayers()
	local count = #players
	local interval = Balance.Idle.SettleInterval
	for index, player in players do
		local data, session = ensure(player)
		if data and session then
			local due = session.nextSettleAt
			if due == nil then
				due = now + (index - 1) * interval / math.max(count, 1)
				session.nextSettleAt = due
			end
			local endsAt = session.boostEndsAt
			if now >= due then
				settleCore(player, data, session, now)
				local nextAt = due + interval
				session.nextSettleAt = if nextAt <= now then now + interval else nextAt
			elseif endsAt ~= nil and endsAt <= now then
				settleCore(player, data, session, now)
			end
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Revenu passif et multiplicateur
-- ---------------------------------------------------------------------------------------------

-- Règle le revenu passif dû ; retourne le Glow crédité
function EconomyService.settle(player: Player): number
	local data, session = ensure(player)
	if not data or not session then
		return 0
	end
	return settleCore(player, data, session, Clock.now())
end

-- Recalcule idleRate après un changement de M ou de perchIncome. Règle d'abord au taux
-- ENREGISTRÉ (toujours exact, même si l'appelant a déjà réglé).
function EconomyService.refreshRate(player: Player)
	local data, session = ensure(player)
	if not data or not session then
		return
	end
	local now = Clock.now()
	settleCore(player, data, session, now)
	applyRate(player, data, session, now)
end

function EconomyService.idleRate(player: Player): number
	local data = ensure(player)
	return if data then data.idleRate else 0
end

function EconomyService.multiplier(player: Player): number
	local data = ensure(player)
	if not data then
		return 1
	end
	return multiplierAt(player, data, Clock.now())
end

-- ---------------------------------------------------------------------------------------------
-- Glow
-- ---------------------------------------------------------------------------------------------

-- Ajoute du Glow (floor, ≥ 0) ; retourne le montant crédité. sku : itemSku analytique (§14.2)
function EconomyService.addGlow(player: Player, amount: number, sku: string, txType: string?): number
	local data, session = ensure(player)
	if not data or not session or money(amount) <= 0 then
		return 0
	end
	settleCore(player, data, session, Clock.now())
	return addGlowRaw(player, data, amount, sku, txType)
end

-- Glow = `seconds` de revenu passif actuel (min `minGlow`) ; retourne le montant crédité
function EconomyService.addGlowSeconds(player: Player, seconds: number, sku: string, minGlow: number?): number
	local data, session = ensure(player)
	if not data or not session then
		return 0
	end
	settleCore(player, data, session, Clock.now())
	local amount = Formulas.glowForSeconds(data.idleRate, seconds, minGlow)
	return addGlowRaw(player, data, amount, sku, nil)
end

function EconomyService.trySpendGlow(player: Player, amount: number, sku: string): boolean
	local data, session = ensure(player)
	if not data or not session or not finite(amount) or amount < 0 then
		return false
	end
	local cost = math.ceil(amount)
	settleCore(player, data, session, Clock.now())
	if data.glow < cost then
		return false
	end
	if cost > 0 then
		data.glow -= cost
		DataService.markDirty(player, "glow")
		Analytics.spend(player, "Glow", cost, data.glow, txTypeFor(sku), sku)
	end
	return true
end

-- ---------------------------------------------------------------------------------------------
-- Stardust
-- ---------------------------------------------------------------------------------------------

function EconomyService.addStardust(player: Player, amount: number, sku: string, txType: string?): number
	local data = ensure(player)
	if not data then
		return 0
	end
	return addStardustRaw(player, data, amount, sku, txType)
end

-- Stardust soumise à un plafond du jour (capKey ∈ snipDust | wispDust | cheers | duo) ; retourne
-- l'accordé (0 → l'appelant envoie Feedback capReached)
function EconomyService.addStardustCapped(player: Player, amount: number, capKey: string, sku: string): number
	local data = ensure(player)
	local wanted = money(amount)
	if not data or wanted <= 0 or type(capKey) ~= "string" then
		return 0
	end
	local caps = capsFor(player, data)
	local used = caps[capKey]
	local granted
	if type(used) == "boolean" then
		-- une fois par jour (cadeau Duo)
		if used then
			return 0
		end
		caps[capKey] = true
		granted = wanted
	else
		local limit = Balance.DailyCaps[capKey]
		if type(limit) ~= "number" then
			warn(`[EconomyService] plafond du jour inconnu : {capKey}`)
			return 0
		end
		local spent = money(used)
		if COUNT_CAPS[capKey] then
			if spent >= limit then
				return 0
			end
			caps[capKey] = spent + 1
			granted = wanted
		else
			granted = math.min(wanted, limit - spent)
			if granted <= 0 then
				return 0
			end
			caps[capKey] = spent + granted
		end
	end
	DataService.markDirty(player, "caps")
	return addStardustRaw(player, data, granted, sku, nil)
end

function EconomyService.trySpendStardust(player: Player, amount: number, sku: string): boolean
	local data = ensure(player)
	if not data or not finite(amount) or amount < 0 then
		return false
	end
	local cost = math.ceil(amount)
	if data.stardust < cost then
		return false
	end
	if cost > 0 then
		data.stardust -= cost
		DataService.markDirty(player, "stardust")
		Analytics.spend(player, "Stardust", cost, data.stardust, txTypeFor(sku), sku)
	end
	return true
end

-- ---------------------------------------------------------------------------------------------
-- Parades, améliorations, Supernova
-- ---------------------------------------------------------------------------------------------

-- Glow d'une parade (M au moment de la parade, Zen, Balise) — n'ajoute rien
function EconomyService.paradeGlow(player: Player, codes: { Types.NebbyCode }, atBeacon: boolean): number
	local data = ensure(player)
	if not data then
		return 0
	end
	local M = multiplierAt(player, data, Clock.now())
	return Formulas.paradeGlow(codes, M, NestService.isZen(player), atBeacon == true)
end

function EconomyService.upgradeLevel(player: Player, track: Types.UpgradeTrack): number
	local data = DataService.get(player)
	if not data or type(data.upgrades) ~= "table" then
		return 0
	end
	return money(data.upgrades[track])
end

function EconomyService.supernovas(player: Player): number
	local data = DataService.get(player)
	return if data then money(data.supernovas) else 0
end

-- Achète le niveau suivant d'une piste (handler du remote BuyUpgrade, exposé pour les tests).
-- (réussi, clé de Feedback du refus)
function EconomyService.buyUpgrade(player: Player, track: Types.UpgradeTrack): (boolean, string?)
	local def = Balance.Upgrades[track]
	local data, session = ensure(player)
	if def == nil or not data or not session then
		return false, nil
	end
	settleCore(player, data, session, Clock.now())
	local level = money(data.upgrades[track])
	if level >= Formulas.upgradeMaxLevel(track, data.supernovas) then
		Notify.feedback(player, "feedback.maxLevel", {}, "warning")
		return false, "feedback.maxLevel"
	end
	local cost = Formulas.upgradeCost(track, level)
	if not finite(cost) or data.glow < cost then
		local missing = if finite(cost) then cost - data.glow else 0
		Notify.feedback(player, "feedback.notEnoughGlow", { missing = missing }, "error")
		return false, "feedback.notEnoughGlow"
	end
	local newLevel = level + 1
	data.glow -= cost
	data.upgrades[track] = newLevel
	DataService.markDirty(player, "glow")
	DataService.markDirty(player, "upgrades")
	Analytics.spend(player, "Glow", cost, data.glow, "Shop", `Upgrade_{track}_{newLevel}`)
	applyGuardLinks(player, data)
	Signals.UpgradeBought:Fire(player, track, newLevel)
	Notify.celebrate(player, "upgrade", { track = track, level = newLevel })
	Invariants.check(player, data, `BuyUpgrade {track}`)
	return true, nil
end

-- Pistes remises à zéro / conservées par une Supernova (Config : ResetOnSupernova)
local function resetTracks(): ({ string }, { string })
	local resets, keeps = {}, {}
	for _, track in Balance.UpgradeOrder do
		local def = Balance.Upgrades[track]
		if def and def.ResetOnSupernova then
			table.insert(resets, track)
		else
			table.insert(keeps, track)
		end
	end
	return resets, keeps
end

-- Supernova (handler du remote Supernova, exposé pour les tests). (réussi, clé de Feedback du refus)
function EconomyService.trySupernova(player: Player): (boolean, string?)
	local data, session = ensure(player)
	if not data or not session then
		return false, nil
	end
	-- port sûr vérifié sur la position validée (une téléportation au Nid le temps du remote
	-- n'encaisse rien : le crochet ci-dessous force une parade sans passer la porte)
	if not NestService.inOwnHarbor(player) then
		Notify.feedback(player, "feedback.notInHarbor", {}, "warning")
		return false, "feedback.notInHarbor"
	end
	-- la file en cours est encaissée d'abord (parade normale, forcée)
	local banker = lineBanker
	if banker then
		local ok, err = pcall(banker, player)
		if not ok then
			warn("[EconomyService] encaissement de la file avant Supernova :", err)
		end
		-- le profil peut survivre au départ (sauvegarde en cours) : revérifier aussi la présence
		if DataService.get(player) ~= data or player.Parent == nil then
			return false, nil
		end
	end
	settleCore(player, data, session, Clock.now())
	local R = data.supernovas
	local cost = Formulas.supernovaCost(R)
	if data.glow < cost then
		Notify.feedback(player, "feedback.notEnoughGlow", { missing = cost - data.glow }, "error")
		return false, "feedback.notEnoughGlow"
	end
	local newR = R + 1
	local removed = data.glow
	data.glow = 0
	data.glowCarry = 0
	local resets = resetTracks()
	for _, track in resets do
		data.upgrades[track] = 0
	end
	data.supernovas = newR
	DataService.markDirty(player, "glow")
	DataService.markDirty(player, "glowCarry")
	DataService.markDirty(player, "upgrades")
	DataService.markDirty(player, "supernovas")
	Analytics.spend(player, "Glow", removed, 0, "Gameplay", `Supernova_{newR}`)
	Analytics.event(player, "SupernovaReached", newR)
	applyRate(player, data, session, Clock.now())
	applyGuardLinks(player, data) -- Guard Links conservés (Config : ResetOnSupernova)
	Signals.Supernova:Fire(player, newR)
	Notify.banner("supernova", { userId = player.UserId, name = player.DisplayName, level = newR }, player)
	Notify.celebrate(player, "supernova", { level = newR })
	Invariants.check(player, data, "Supernova")
	return true, nil
end

function EconomyService.supernovaPreview(player: Player): Types.SupernovaPreview
	local data, session = ensure(player)
	local R = 0
	local glow = 0
	if data and session then
		settleCore(player, data, session, Clock.now())
		R = data.supernovas
		glow = data.glow
	end
	local cost = Formulas.supernovaCost(R)
	local per = Balance.Multiplier.PerSupernova
	local auraNow, auraNext = Formulas.auraFor(R), Formulas.auraFor(R + 1)
	local resetList, keptTracks = resetTracks()
	local resets = { "glow" }
	for _, track in resetList do
		table.insert(resets, track)
	end
	local keeps = { "nebbies" }
	for _, track in keptTracks do
		table.insert(keeps, track)
	end
	for _, key in { "stardust", "atlas", "cosmetics", "quests", "stats" } do
		table.insert(keeps, key)
	end
	return {
		level = R,
		cost = cost,
		glow = glow,
		canAfford = glow >= cost,
		inHarbor = data ~= nil and NestService.inOwnHarbor(player),
		incomeNow = per * R,
		incomeNext = per * (R + 1),
		congaCapNow = Formulas.upgradeMaxLevel("conga", R),
		congaCapNext = Formulas.upgradeMaxLevel("conga", R + 1),
		dashNow = Formulas.dashCooldown(R),
		dashNext = Formulas.dashCooldown(R + 1),
		auraNext = if auraNext ~= auraNow then auraNext else nil,
		resets = resets,
		keeps = keeps,
	}
end

-- ---------------------------------------------------------------------------------------------
-- Boosts, équipiers, crochet de file
-- ---------------------------------------------------------------------------------------------

function EconomyService.grantPersonalBoost(player: Player, seconds: number)
	local data, session = ensure(player)
	if not data or not session or not finite(seconds) or seconds <= 0 then
		return
	end
	local now = Clock.now()
	settleCore(player, data, session, now)
	local boosts = data.boosts
	boosts.personalUntil = math.ceil(math.max(now, boosts.personalUntil) + seconds)
	DataService.markDirty(player, "boosts")
	applyRate(player, data, session, now)
end

function EconomyService.hasBoost(player: Player): boolean
	local data = DataService.get(player)
	local now = Clock.now()
	if data and type(data.boosts) == "table" and finite(data.boosts.personalUntil) then
		if data.boosts.personalUntil > now then
			return true
		end
	end
	return serverBoostUntil > now
end

-- Poussé par EventService : fin du boost ×2 de serveur (0 = aucun)
function EconomyService.setServerBoostUntil(t: number)
	if not finite(t) or t < 0 then
		return
	end
	if t == serverBoostUntil then
		return
	end
	local now = Clock.now()
	-- règle tout le monde à l'ancien taux, change le boost, puis recalcule
	local touched = {}
	for _, player in Players:GetPlayers() do
		local data, session = ensure(player)
		if data and session then
			settleCore(player, data, session, now)
			table.insert(touched, { player = player, data = data, session = session })
		end
	end
	serverBoostUntil = t
	for _, entry in touched do
		applyRate(entry.player, entry.data, entry.session, now)
	end
end

-- Poussé par CrewService : équipiers présents et actifs (bonus +10 % chacun, max 3)
function EconomyService.setCrewPresent(player: Player, count: number)
	local n = money(count)
	if (crewPresent[player] or 0) == n then
		return
	end
	if player.Parent == nil then
		return
	end
	local data, session = ensure(player)
	if data and session then
		local now = Clock.now()
		settleCore(player, data, session, now)
		crewPresent[player] = if n > 0 then n else nil
		applyRate(player, data, session, now)
	else
		crewPresent[player] = if n > 0 then n else nil
	end
end

-- Crochet posé par CongaService.Init : encaisse la file du joueur (parade forcée) avant une Supernova
function EconomyService.setLineBanker(fn: (Player) -> ())
	lineBanker = fn
end

return EconomyService
