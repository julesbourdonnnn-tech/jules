--!strict
-- Prix Robux lus en direct depuis Roblox (tarification régionale et tests de prix gérés),
-- avec repli sur le prix de la config tant que la réponse n'est pas arrivée.
--   Prices.observe("pass", def.id, def.price, function(price) label.Text = "R$ " .. price end)

local MarketplaceService = game:GetService("MarketplaceService")

local Prices = {}

local cache: { [string]: number } = {}
local pending: { [string]: { (number) -> () } } = {}

local function fetch(kind: "pass" | "product", id: number, key: string)
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(
			id,
			if kind == "pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
		)
	end)
	local callbacks = pending[key] or {}
	pending[key] = nil
	if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
		cache[key] = info.PriceInRobux
		for _, cb in callbacks do
			task.spawn(cb, info.PriceInRobux)
		end
	end
end

-- Appelle `onPrice(fallback)` tout de suite, puis `onPrice(prixRéel)` dès qu'il est connu.
function Prices.observe(kind: "pass" | "product", id: number, fallback: number, onPrice: (number) -> ())
	if id <= 0 then
		onPrice(fallback)
		return
	end
	local key = kind .. ":" .. tostring(id)
	local cached = cache[key]
	if cached then
		onPrice(cached)
		return
	end
	onPrice(fallback)
	if pending[key] then
		table.insert(pending[key], onPrice)
		return
	end
	pending[key] = { onPrice }
	task.spawn(fetch, kind, id, key)
end

return Prices
