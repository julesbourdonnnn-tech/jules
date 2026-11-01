--!strict
-- ProductService (paquet ranch, docs/04 §11.12 ; GDD §8). Effets des passes et des produits par
-- MonetizationService (socle : reçu idempotent, acquitté après sauvegarde) :
--   * Squish Party (EventService.startSquishParty : démarre, ou PROLONGE de 600 s une fête en cours
--     quand deux reçus se croisent ; refusée seulement quand le plafond du jour caps.partyBuys est
--     atteint : rend false, Roblox ne débite pas) ; l'acheteur qui part avant la fin garde ses secondes
--     achetées et non jouées (EventService.partyUnplayed, ≤ 600 par achat) en boost personnel, accordé
--     dans DataService.onBeforeSave(release = true) — départ ET BindToClose — jamais dans
--     PlayerRemoving (docs/04 §1 règle 15) : écrit dans la sauvegarde de départ, présent exactement une
--     fois sur le serveur suivant ;
--   * tenues (garde-robe outfits.owned[id] += 1 par SquishyService.grantOutfit).
-- Paquets de pièces RETIRÉS du lancement (contrat v1.2, GDD v1.3 §8.3) : CoinsSmall et CoinsBig restent
-- dans Config/Monetization (id 0, hidden) SANS handler. Passes : ×2 Pièces (EconomyService.refresh,
-- appliqué une seule fois), Grand Ranch (capacité relue en direct par SquishyService), Pot automatique
-- (EconomyService.step). PolicyService au chargement (pcall) : seulement l'analytique
-- PolicyPaidRandomRestricted (aucun article caché, aucun attribut PolicyNoCoins).
-- Clés : aucune (passes : MonetizationService ; caps.partyBuys : EconomyService.consumeCap ;
-- outfits : SquishyService ; boosts : EconomyService.grantPersonalBoost).

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared.Util.Clock)
local Balance = require(Shared.Config.Balance)
local Monetization = require(Shared.Config.Monetization)
local Notify = require(script.Parent.Parent.Util.Notify)
local Analytics = require(script.Parent.Parent.Util.Analytics)
local Guard = require(script.Parent.Parent.Ranch.Guard)
local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local EconomyService = require(script.Parent.EconomyService)
local SquishyService = require(script.Parent.SquishyService)
local EventService = require(script.Parent.EventService)

local ProductService = {}

-- acheteurs d'une Squish Party sur ce serveur (UserId) : seuls ceux-là ont des secondes non jouées
local buyers: { [number]: boolean } = {}

local function purchased(player: Player, key: string)
	Notify.celebrate(player, "purchase", { key = key })
	Analytics.event(player, "Product_" .. key, 1)
end

-- Squish Party : refus seulement au plafond du jour (rend false : Roblox ne débite pas et pourra
-- réessayer) ; pendant une fête, EventService la prolonge de 600 s (jamais refusé)
local function grantParty(player: Player, data: { [string]: any }): boolean
	if ProductService.partyBuysToday(player) >= Balance.Caps.partyBuys then
		return false
	end
	local showName = type(data.settings) == "table" and data.settings.partyShowName == true
	local ok, started = pcall(EventService.startSquishParty, player, showName)
	if not ok then
		Guard.caught("product:SquishParty", started)
		return false -- rien n'est accordé ni compté : le reçu sera réessayé
	end
	if started ~= true then
		return false
	end
	EconomyService.consumeCap(player, "partyBuys", 1)
	buyers[player.UserId] = true
	purchased(player, "SquishParty")
	return true
end

local function outfitHandler(key: string): (Player, { [string]: any }) -> boolean
	return function(player: Player, _data: { [string]: any }): boolean
		local def = Monetization.Products[key]
		local outfit = def and def.outfit
		if type(outfit) ~= "string" then
			return false
		end
		local before = SquishyService.grantOutfit(player, outfit, 0)
		local after = SquishyService.grantOutfit(player, outfit, 1)
		if after <= before then
			return false
		end
		purchased(player, key)
		return true
	end
end

-- Secondes de Squish Party achetées et non jouées → boost personnel, dans la sauvegarde de départ
local function onBeforeSave(player: Player, _data: { [string]: any }, release: boolean?)
	if not release or not buyers[player.UserId] then
		return
	end
	buyers[player.UserId] = nil -- une seule fois (même si une autre sauvegarde de départ suivait)
	local ok, unplayed = pcall(EventService.partyUnplayed, player.UserId)
	if not ok then
		Guard.caught("product:partyUnplayed", unplayed)
		return
	end
	if type(unplayed) == "number" and unplayed == unplayed and unplayed > 0 and unplayed < math.huge then
		EconomyService.grantPersonalBoost(player, unplayed)
	end
end

local function checkPolicy(player: Player)
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	if ok and type(info) == "table" and player.Parent ~= nil then
		Analytics.event(
			player,
			"PolicyPaidRandomRestricted",
			if info.ArePaidRandomItemsRestricted then 1 else 0
		)
	end
end

-- Création des remotes et des états ; aucun yield long
function ProductService.Init()
	MonetizationService.registerProduct("SquishParty", grantParty)
	for key, def in Monetization.Products do
		if def.outfit ~= nil and not def.hidden then
			MonetizationService.registerProduct(key, outfitHandler(key))
		end
	end
	-- paquets de pièces (hidden) : aucun handler (retirés du lancement)
	DataService.onBeforeSave(onBeforeSave)
end

-- Connexions et boucles
function ProductService.Start()
	MonetizationService.PassGranted:Connect(function(player: Player, passKey: string)
		-- ×2 Pièces : appliqué une seule fois (P dans le contexte du revenu) ; Grand Ranch : capacité
		-- relue en direct ; Pot automatique : lu par EconomyService.step
		if passKey == "DoubleCoins" then
			EconomyService.refresh(player)
		end
	end)
	MonetizationService.PassPurchased:Connect(function(player: Player, passKey: string)
		purchased(player, passKey)
	end)
	DataService.Loaded:Connect(function(player: Player)
		task.spawn(checkPolicy, player)
	end)
	for _, player in Players:GetPlayers() do
		if DataService.isLoaded(player) then
			task.spawn(checkPolicy, player)
		end
	end
end

-- Squish Parties achetées aujourd'hui (caps.partyBuys, remis à zéro au changement de jour UTC)
function ProductService.partyBuysToday(player: Player): number
	local data = DataService.get(player)
	if data == nil or type(data.caps) ~= "table" then
		return 0
	end
	if data.caps.day ~= Clock.day() then
		return 0
	end
	local n = data.caps.partyBuys
	return if type(n) == "number" and n == n then math.max(0, math.floor(n)) else 0
end

return ProductService
