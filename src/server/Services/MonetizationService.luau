--!strict
-- MonetizationService : achats Robux fiables.
--  * ProcessReceipt unique et idempotent (PurchaseId mémorisés dans data.receipts)
--  * gamepasses : vérifiés à l'arrivée + achat en jeu, exposés au client via data.passes
--
-- API :
--   MonetizationService.registerProduct("Coins1000", function(player, data) ... return true end)
--   MonetizationService.ownsPass(player, "VIP") -> boolean
--   MonetizationService.PassGranted:Connect(function(player, passKey) end)

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared.Config.Monetization)
local Signal = require(Shared.Util.Signal)
local DataService = require(script.Parent.DataService)

local MAX_STORED_RECEIPTS = 100
local RECEIPT_DATA_TIMEOUT = 15

type ProductHandler = (player: Player, data: { [string]: any }) -> boolean

local MonetizationService = {}
MonetizationService.PassGranted = Signal.new() :: Signal.Signal<Player, string>
MonetizationService.ProductGranted = Signal.new() :: Signal.Signal<Player, string>

local handlers: { [string]: ProductHandler } = {}
local productKeyById: { [number]: string } = {}
local passKeyById: { [number]: string } = {}

function MonetizationService.registerProduct(productKey: string, handler: ProductHandler)
	assert(Monetization.Products[productKey], `Produit inconnu : {productKey}`)
	assert(handlers[productKey] == nil, `Handler déjà enregistré : {productKey}`)
	handlers[productKey] = handler
end

function MonetizationService.ownsPass(player: Player, passKey: string): boolean
	local data = DataService.get(player)
	return data ~= nil and type(data.passes) == "table" and data.passes[passKey] == true
end

-- Mémorise la possession ; `announce` déclenche PassGranted (effets en jeu)
local function grantPass(player: Player, passKey: string, announce: boolean)
	local data = DataService.get(player)
	if not data then
		return
	end
	if type(data.passes) ~= "table" then
		data.passes = {}
	end
	if data.passes[passKey] then
		return
	end
	data.passes[passKey] = true
	DataService.markDirty(player, "passes")
	if announce then
		MonetizationService.PassGranted:Fire(player, passKey)
	end
end

local function checkPasses(player: Player)
	for passKey, def in Monetization.Passes do
		if def.id > 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.id)
			end)
			if player.Parent == nil then
				return
			end
			if ok and owns then
				grantPass(player, passKey, false)
			elseif not ok then
				warn(`[Monetization] vérification du pass {passKey} impossible pour {player.Name} :`, owns)
			end
		end
	end
	-- chaque pass possédé déclenche ses effets une fois par session
	local data = DataService.get(player)
	if data and type(data.passes) == "table" then
		for passKey, owned in data.passes do
			if owned and Monetization.Passes[passKey] then
				MonetizationService.PassGranted:Fire(player, passKey)
			end
		end
	end
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = DataService.waitFor(player, RECEIPT_DATA_TIMEOUT)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if type(data.receipts) ~= "table" then
		data.receipts = {}
	end
	if table.find(data.receipts, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local productKey = productKeyById[receipt.ProductId]
	local handler = productKey and handlers[productKey]
	if not productKey or not handler then
		warn("[Monetization] produit sans handler :", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(handler, player, data)
	if not ok then
		warn(`[Monetization] erreur dans le handler {productKey} :`, granted)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if granted ~= true then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(data.receipts, receipt.PurchaseId)
	while #data.receipts > MAX_STORED_RECEIPTS do
		table.remove(data.receipts, 1)
	end
	MonetizationService.ProductGranted:Fire(player, productKey)
	-- Si la sauvegarde échoue, Roblox redemandera : le reçu en mémoire évite le double crédit.
	if not DataService.saveNow(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService.Init()
	for key, def in Monetization.Products do
		if def.id > 0 then
			assert(productKeyById[def.id] == nil, `ID de produit en double : {def.id}`)
			productKeyById[def.id] = key
		end
	end
	for key, def in Monetization.Passes do
		if def.id > 0 then
			assert(passKeyById[def.id] == nil, `ID de pass en double : {def.id}`)
			passKeyById[def.id] = key
		end
	end
end

function MonetizationService.Start()
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, wasPurchased: boolean)
			local passKey = passKeyById[passId]
			if wasPurchased and passKey then
				grantPass(player, passKey, true)
			end
		end
	)

	DataService.Loaded:Connect(function(player: Player)
		checkPasses(player)
	end)
	for _, player in Players:GetPlayers() do
		if DataService.isLoaded(player) then
			task.spawn(checkPasses, player)
		end
	end
end

-- Exposé pour les tests
MonetizationService._processReceipt = processReceipt

return MonetizationService
