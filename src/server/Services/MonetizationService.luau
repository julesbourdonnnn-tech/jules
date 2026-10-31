--!strict
-- MonetizationService : achats Robux fiables.
--  * ProcessReceipt unique et idempotent (PurchaseId mémorisés dans data.receipts)
--  * gamepasses : vérifiés à l'arrivée + achat en jeu, exposés au client via data.passes.
--    UserOwnsGamePassAsync fait foi : PromptGamePassPurchaseFinished n'est qu'un indice (un exploit
--    peut l'émettre avec wasPurchased = true) ; un pass enregistré mais plus possédé (remboursé,
--    ou accordé autrefois sur un signal non vérifié) est retiré à l'arrivée.
--
-- API :
--   MonetizationService.registerProduct("Coins1000", function(player, data) ... return true end)
--   MonetizationService.ownsPass(player, "VIP") -> boolean
--   MonetizationService.PassGranted:Connect(function(player, passKey) end)   -- arrivée + achat
--   MonetizationService.PassPurchased:Connect(function(player, passKey) end) -- achat en jeu VÉRIFIÉ
--   MonetizationService.PassRevoked:Connect(function(player, passKey) end)   -- retiré à l'arrivée

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared.Config.Monetization)
local Signal = require(Shared.Util.Signal)
local DataService = require(script.Parent.DataService)

local MAX_STORED_RECEIPTS = 100
local RECEIPT_DATA_TIMEOUT = 15

-- Réglages (modifiables par les tests avant le démarrage)
local Settings = {
	VERIFY_ATTEMPTS = 3, -- vérifications de possession après un achat en jeu
	VERIFY_RETRY_DELAY = 2, -- s, multiplié par le numéro de l'essai
}

type ProductHandler = (player: Player, data: { [string]: any }) -> boolean

local MonetizationService = {}
MonetizationService.Settings = Settings
MonetizationService.PassGranted = Signal.new() :: Signal.Signal<Player, string>
MonetizationService.ProductGranted = Signal.new() :: Signal.Signal<Player, string>
-- Achat en jeu confirmé par UserOwnsGamePassAsync (remerciements, analytique de revenus)
MonetizationService.PassPurchased = Signal.new() :: Signal.Signal<Player, string>
-- Pass enregistré mais plus possédé (remboursé, ou accordé jadis sans vérification) : effets à retirer
MonetizationService.PassRevoked = Signal.new() :: Signal.Signal<Player, string>

local handlers: { [string]: ProductHandler } = {}
local productKeyById: { [number]: string } = {}
local passKeyById: { [number]: string } = {}
-- vérifications d'achat en cours, et passes confirmés par Roblox pendant cette session
local verifying: { [Player]: { [string]: boolean } } = {}
local confirmed: { [Player]: { [string]: boolean } } = {}

function MonetizationService.registerProduct(productKey: string, handler: ProductHandler)
	assert(Monetization.Products[productKey], `Produit inconnu : {productKey}`)
	assert(handlers[productKey] == nil, `Handler déjà enregistré : {productKey}`)
	handlers[productKey] = handler
end

function MonetizationService.ownsPass(player: Player, passKey: string): boolean
	local data = DataService.get(player)
	return data ~= nil and type(data.passes) == "table" and data.passes[passKey] == true
end

local function markConfirmed(player: Player, passKey: string)
	local set = confirmed[player]
	if set == nil then
		set = {}
		confirmed[player] = set
	end
	set[passKey] = true
end

-- Mémorise la possession ; `announce` déclenche PassGranted (effets en jeu).
-- Renvoie true si le pass vient d'être accordé (il ne l'était pas encore).
local function grantPass(player: Player, passKey: string, announce: boolean): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	if type(data.passes) ~= "table" then
		data.passes = {}
	end
	if data.passes[passKey] then
		return false
	end
	data.passes[passKey] = true
	DataService.markDirty(player, "passes")
	if announce then
		MonetizationService.PassGranted:Fire(player, passKey)
	end
	return true
end

-- Roblox affirme que le joueur ne possède pas (ou plus) ce pass : retiré du profil
local function revokePass(player: Player, passKey: string)
	local data = DataService.get(player)
	if not data or type(data.passes) ~= "table" or data.passes[passKey] == nil then
		return
	end
	local set = confirmed[player]
	if set and set[passKey] then
		return -- acheté et vérifié pendant cette session (réponse arrivée entre-temps)
	end
	data.passes[passKey] = nil
	DataService.markDirty(player, "passes")
	warn(`[Monetization] pass {passKey} non possédé par {player.Name} : retiré du profil`)
	MonetizationService.PassRevoked:Fire(player, passKey)
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
			if ok and owns == true then
				markConfirmed(player, passKey)
				grantPass(player, passKey, false)
			elseif ok then
				revokePass(player, passKey)
			else
				-- panne : on garde la valeur enregistrée (jamais de retrait sans réponse de Roblox)
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

-- Achat en jeu : PromptGamePassPurchaseFinished n'est qu'un indice, la possession est confirmée
-- par UserOwnsGamePassAsync avant tout octroi (quelques essais : panne ou propagation lente).
-- Un acheteur légitime non confirmé ici récupère son pass à l'arrivée suivante (checkPasses).
local function verifyPurchase(player: Player, passKey: string, passId: number)
	if player.Parent == nil then
		return -- déjà parti : rien à mémoriser
	end
	local mine = verifying[player]
	if mine == nil then
		mine = {}
		verifying[player] = mine
	end
	if mine[passKey] or MonetizationService.ownsPass(player, passKey) then
		return -- déjà vérifié ou en cours (signal répété)
	end
	mine[passKey] = true
	for attempt = 1, Settings.VERIFY_ATTEMPTS do
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
		end)
		if player.Parent == nil then
			break
		end
		if ok and owns == true then
			markConfirmed(player, passKey)
			if grantPass(player, passKey, true) then
				MonetizationService.PassPurchased:Fire(player, passKey)
			end
			break
		end
		if attempt >= Settings.VERIFY_ATTEMPTS then
			warn(
				`[Monetization] achat du pass {passKey} non confirmé par Roblox pour {player.Name} :`,
				if ok then "non possédé" else owns
			)
		else
			task.wait(Settings.VERIFY_RETRY_DELAY * attempt)
		end
	end
	if verifying[player] == mine then
		mine[passKey] = nil
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
			local passKey = if type(passId) == "number" then passKeyById[passId] else nil
			if wasPurchased == true and passKey then
				task.spawn(verifyPurchase, player, passKey, passId)
			end
		end
	)
	Players.PlayerRemoving:Connect(function(player: Player)
		verifying[player] = nil
		confirmed[player] = nil
	end)

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
