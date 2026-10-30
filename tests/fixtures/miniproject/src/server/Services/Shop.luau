--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local Config = require(ReplicatedStorage.Shared.Config)
local Shop = { coins = {} :: { [Player]: number } }
function Shop.Init()
	local remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
	local buy = Instance.new("RemoteEvent")
	buy.Name = "Buy"
	buy.Parent = remotes
	local result = Instance.new("RemoteEvent")
	result.Name = "Result"
	result.Parent = remotes
	buy.OnServerEvent:Connect(function(player, itemId)
		if typeof(itemId) ~= "string" then return end
		local item = Config.Items[itemId]
		if not item then return end
		if Shop.coins[player] >= item.cost then
			Shop.coins[player] -= item.cost
			result:FireClient(player, true, Shop.coins[player])
		else
			result:FireClient(player, false, Shop.coins[player])
		end
	end)
end
function Shop.Start()
	local store = DataStoreService:GetDataStore("Test")
	local function onAdded(p: Player)
		Shop.coins[p] = (store:GetAsync("p" .. p.UserId) or Config.StartCoins)
	end
	Players.PlayerAdded:Connect(onAdded)
	for _, p in Players:GetPlayers() do task.spawn(onAdded, p) end
	Players.PlayerRemoving:Connect(function(p)
		store:SetAsync("p" .. p.UserId, Shop.coins[p])
		Shop.coins[p] = nil
	end)
end
return Shop
