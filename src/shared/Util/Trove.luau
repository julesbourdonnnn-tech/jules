--!strict
-- Trove : regroupe tout ce qu'il faut nettoyer (connexions, instances, threads,
-- fonctions) et le libère d'un coup avec :Clean(). Évite les fuites mémoire.

export type Trove = {
	Add: <T>(self: Trove, item: T) -> T,
	Connect: (self: Trove, signal: RBXScriptSignal, fn: (...any) -> ()) -> RBXScriptConnection,
	Clean: (self: Trove) -> (),
	Destroy: (self: Trove) -> (),
	_items: { any },
	_cleaning: boolean,
}

local Trove = {}
Trove.__index = Trove

function Trove.new(): Trove
	return setmetatable({ _items = {}, _cleaning = false }, Trove) :: any
end

local function cleanup(item: any)
	local t = typeof(item)
	if t == "RBXScriptConnection" then
		item:Disconnect()
	elseif t == "Instance" then
		item:Destroy()
	elseif t == "function" then
		item()
	elseif t == "thread" then
		if coroutine.status(item) ~= "dead" then
			pcall(task.cancel, item)
		end
	elseif type(item) == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		elseif type(item.Clean) == "function" then
			item:Clean()
		end
	end
end

function Trove.Add<T>(self: Trove, item: T): T
	if self._cleaning then
		cleanup(item)
		return item
	end
	table.insert(self._items, item)
	return item
end

function Trove.Connect(self: Trove, signal: RBXScriptSignal, fn: (...any) -> ()): RBXScriptConnection
	return self:Add(signal:Connect(fn))
end

function Trove.Clean(self: Trove)
	if self._cleaning then
		return
	end
	self._cleaning = true
	local items = self._items
	self._items = {}
	for i = #items, 1, -1 do
		local ok, err = pcall(cleanup, items[i])
		if not ok then
			warn("[Trove] nettoyage échoué :", err)
		end
	end
	self._cleaning = false
end

Trove.Destroy = Trove.Clean

return Trove
