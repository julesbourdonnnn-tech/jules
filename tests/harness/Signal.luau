--!nocheck
-- Signal minimal compatible RBXScriptSignal (Connect / Once / Wait / Fire) pour les tests.

local task = require("@lune/task")

export type Connection = { Connected: boolean, Disconnect: (self: Connection) -> () }

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} :: { any } }, Signal)
end

function Signal:Connect(fn: (...any) -> ())
	local handlers = self._handlers
	local conn
	conn = {
		Connected = true,
		_fn = fn,
		Disconnect = function(c)
			c.Connected = false
			local i = table.find(handlers, c)
			if i then
				table.remove(handlers, i)
			end
		end,
	}
	table.insert(handlers, conn)
	return conn
end

function Signal:Once(fn: (...any) -> ())
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

-- Erreurs levées dans les connexions (comme la sortie rouge de Studio) ;
-- Test.it fait échouer le test si cette liste grossit pendant son exécution.
Signal.errors = {} :: { string }

local function runHandler(fn, ...)
	local ok, err = xpcall(fn, function(e)
		return tostring(e) .. "\n" .. debug.traceback(nil, 2)
	end, ...)
	if not ok then
		table.insert(Signal.errors, err)
	end
end

-- Comme Roblox : chaque connexion s'exécute dans son propre thread (task.spawn),
-- donc un handler qui yield ne bloque pas l'émetteur.
function Signal:Fire(...: any)
	for _, conn in table.clone(self._handlers) do
		if conn.Connected then
			task.spawn(runHandler, conn._fn, ...)
		end
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	for _, conn in table.clone(self._handlers) do
		conn:Disconnect()
	end
end

return Signal
