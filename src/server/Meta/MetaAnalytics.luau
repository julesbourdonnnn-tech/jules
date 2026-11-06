--!strict
-- MetaAnalytics (lot A4, étape 6, décision D30 du plan ; GDD v2.0 §16.2-§16.4, docs/04 §27.14) —
-- analytique v2.0 du jeu : écouteurs des signaux v2.0 vers Server/Util/Analytics. Démarré par
-- DiagnosticsService.Start (start) et stépé par DiagnosticsService.step (step, 1 fois par seconde) :
-- aucune ligne de Main.server. Chaque événement est envoyé pour un profil v2 seulement, interrupteur
-- de son système ouvert ; interrupteurs coupés, chaque écouteur rend la main tout de suite (flux
-- d'analytique de la v1.3 identique, requête pour requête ; aucune allocation par tick).
--   * ConfettiChanged (gain, source) [Confetti] → ConfettiEarned cumulé par source (champ source) et
--     économie « Confetti » en unités brutes (solde = profile.confetti) : sources GrandSplorch,
--     PetitSplorch, Skipped, Ascend, Regain, RecordBonus, FullPen, Mastery (Gameplay), WeeklyTrack
--     (TimedReward) ; puits (écart négatif « spend ») : Workshop_<ligne> ou Fun_<ligne>, nom de la ligne
--     achetée juste avant (UpgradeBought part AVANT ConfettiChanged dans le même achat, montant exact) ;
--   * UpgradeBought (id, de, à, monnaie) → Upgrade_<famille> (niveaux achetés, cumulés)
--     [UpgradesScreen] ; WorkshopBuy_<ligne> (niveaux, champ level = niveau atteint) [Workshop] ;
--   * RecordReached (Record R) → RanchTierReached (palier 1-6, Visuals.RanchTiersAt : Record R 1, 3, 5,
--     10, 15, 20) [RanchTiers] ;
--   * NextGoalGap [UpgradesScreen] : secondes de JEU passées plus de GoalGap (180 s) de jeu après le
--     dernier achat ou but (UpgradeBought — dalles comprises —, PrestigeApplied, objectif du jour ou Défi
--     terminé : MetaAnalytics.goal, appelé par QuestService), cumulées par tranche de 5 min. Une seconde
--     est « de jeu » si le joueur a fait une intention acceptée dans les Balance.Helpers.NapAfter
--     dernières secondes (Activity.lastIntent : menus compris, N23) ;
--   * compteurs de Diagnostics transmis (counted : UpgradeStale [UpgradesScreen]) ; ClientMetric (D29)
--     demande isV2 avant de compter une sorte liée à un interrupteur.
-- Jamais une écriture du profil, jamais un message aux clients, jamais une trace.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Features = require(Shared.Config.Features)
local Balance = require(Shared.Config.Balance)
local Visuals = require(Shared.Config.Visuals)

local Server = script.Parent.Parent
local Signals = require(Server.Signals)
local Analytics = require(Server.Util.Analytics)
local Activity = require(Server.Util.Activity)
local PadRules = require(Server.Ranch.PadRules)
local DataService = require(Server.Services.DataService)

local MetaAnalytics = {}

-- Réglages nommés (GDD §16.3-§16.4 : « NextGoalGap > 3 min »)
MetaAnalytics.GoalGap = 180 -- s de jeu après le dernier achat ou but
MetaAnalytics.StepEvery = 1 -- s entre deux comptes du temps de jeu

-- Sources des gains (EconomyService.addConfetti) → itemSku de l'économie (GDD §16.2) et type
local SOURCE_SKU: { [string]: string } = {
	splorch = "GrandSplorch",
	petit = "PetitSplorch",
	skipped = "Skipped",
	ascend = "Ascend",
	regain = "Regain",
	record = "RecordBonus",
	fullPen = "FullPen",
	track = "WeeklyTrack",
	mastery = "Mastery",
}
local SOURCE_TX: { [string]: string } = { track = "TimedReward" }

-- Palier de ranch atteint à ce Record R (1 à 6)
local TIER_AT: { [number]: number } = {}
for i, r in Visuals.RanchTiersAt do
	TIER_AT[r] = i
end

local started = false
local lastStep = -math.huge
-- secondes de jeu depuis le dernier achat ou but (joueurs suivis seulement, UpgradesScreen ouvert)
local playSince: { [Player]: number } = {}
-- puits de Confettis de l'achat en cours (UpgradeBought → ConfettiChanged « spend »)
local pendingSink: { [Player]: string } = {}

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function on(flag: string): boolean
	return Features.get(flag) == true
end

-- Profil v2 chargé du joueur (nil : absent, illisible ou v1)
local function v2Data(player: Player): { [string]: any }?
	local data = DataService.get(player)
	if data ~= nil and PadRules.v2Profile(data) then
		return data
	end
	return nil
end

local function confettiOf(data: { [string]: any }): number
	local c = data.confetti
	return if finite(c) and c > 0 then math.floor(c) else 0
end

-- Le joueur a-t-il un profil v2 chargé ? (ClientMetric, D29)
function MetaAnalytics.isV2(player: Player): boolean
	return typeof(player) == "Instance" and player:IsA("Player") and v2Data(player) ~= nil
end

-- But atteint (achat, prestige, objectif du jour ou Défi terminé) : le compte de NextGoalGap repart
function MetaAnalytics.goal(player: Player)
	if not on("UpgradesScreen") or playSince[player] == nil then
		return
	end
	playSince[player] = 0
end

-- Compteur de Diagnostics transmis à l'analytique (DiagnosticsService.count)
function MetaAnalytics.counted(key: string, player: Player)
	if key == "UpgradeStale" and on("UpgradesScreen") and MetaAnalytics.isV2(player) then
		Analytics.add(player, "UpgradeStale", 1)
	end
end

local function onConfetti(player: Player, delta: number, source: string)
	if not on("Confetti") or not finite(delta) then
		return
	end
	local data = v2Data(player)
	if data == nil then
		return
	end
	local balance = confettiOf(data)
	if delta > 0 then
		local sku = SOURCE_SKU[source]
		if sku ~= nil then
			Analytics.earnConfetti(player, sku, delta, balance, SOURCE_TX[source])
			Analytics.add(player, "ConfettiEarned", delta, { source = sku })
		end
	elseif delta < 0 and source == "spend" then
		local sku = pendingSink[player] or "Workshop_other"
		pendingSink[player] = nil
		Analytics.spendConfetti(player, sku, -delta, balance)
	end
end

local function onUpgrade(player: Player, id: string, from: number, to: number, currency: string)
	MetaAnalytics.goal(player)
	if type(id) ~= "string" or not finite(from) or not finite(to) or to - from < 1 then
		return
	end
	local data = v2Data(player)
	if data == nil then
		return
	end
	local n = math.floor(to - from)
	if currency == "coins" then
		if on("UpgradesScreen") then
			Analytics.add(player, "Upgrade_" .. id, n)
		end
	elseif currency == "confetti" then
		local fun = string.sub(id, 1, 4) == "fun."
		local line = if fun then string.sub(id, 5) else id
		if on("Workshop") then
			Analytics.add(player, "WorkshopBuy_" .. line, n, { level = math.floor(to) })
		end
		if on("Confetti") then
			pendingSink[player] = (if fun or line == "decoShop" then "Fun_" else "Workshop_") .. line
		end
	end
end

local function onRecord(player: Player, bestR: number)
	if not on("RanchTiers") or not finite(bestR) then
		return
	end
	local tier = TIER_AT[bestR]
	if tier ~= nil and v2Data(player) ~= nil then
		Analytics.custom(player, "RanchTierReached", tier, { bestR = bestR })
	end
end

-- Branche les écouteurs (DiagnosticsService.Start, une fois)
function MetaAnalytics.start()
	if started then
		return
	end
	started = true
	Signals.ConfettiChanged:Connect(onConfetti)
	Signals.UpgradeBought:Connect(onUpgrade)
	Signals.RecordReached:Connect(onRecord)
	Signals.PrestigeApplied:Connect(function(player: Player)
		MetaAnalytics.goal(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		playSince[player] = nil
		pendingSink[player] = nil
	end)
end

-- Temps de jeu sans but (DiagnosticsService.step, 10 Hz ; compté une fois par seconde)
function MetaAnalytics.step(now: number)
	if not finite(now) or now - lastStep < MetaAnalytics.StepEvery then
		return
	end
	local dt = math.clamp(now - lastStep, 0, 2 * MetaAnalytics.StepEvery)
	lastStep = now
	if not on("UpgradesScreen") then
		if next(playSince) ~= nil then
			table.clear(playSince)
		end
		return
	end
	local napAfter = Balance.Helpers.NapAfter
	for _, player in Players:GetPlayers() do
		local since = playSince[player]
		if v2Data(player) == nil then
			playSince[player] = nil
		elseif since == nil then
			playSince[player] = 0 -- suivi dès qu'il est vu : délai de GoalGap avant le premier compte
		elseif now - Activity.lastIntent(player) <= napAfter then
			local after = since + dt
			playSince[player] = after
			local over = math.min(dt, after - MetaAnalytics.GoalGap)
			if over > 0 then
				Analytics.add(player, "NextGoalGap", over)
			end
		end
	end
end

-- État (specs) : secondes de jeu depuis le dernier but d'un joueur suivi (nil : pas suivi)
function MetaAnalytics.playSince(player: Player): number?
	return playSince[player]
end

return MetaAnalytics
