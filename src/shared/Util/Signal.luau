--!strict
-- Signal Luau léger (sans Instance) : chaque handler s'exécute dans son propre thread,
-- comme les événements Roblox, pour qu'un handler qui yield ne bloque pas les autres.

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Wait: (self: Signal<T...>) -> T...,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

local Signal = {}
Signal.__index = Signal

local ConnectionClass = {}
ConnectionClass.__index = ConnectionClass

function ConnectionClass.Disconnect(self: any)
	if not self.Connected then
		return
	end
	self.Connected = false
	local list = self._signal._handlers
	local i = table.find(list, self)
	if i then
		table.remove(list, i)
	end
end

function Signal.new<T...>(): Signal<T...>
	return setmetatable({ _handlers = {} }, Signal) :: any
end

function Signal.Connect(self: any, fn: (...any) -> ()): Connection
	local conn = setmetatable({ Connected = true, _fn = fn, _signal = self }, ConnectionClass)
	table.insert(self._handlers, conn)
	return conn :: any
end

function Signal.Once(self: any, fn: (...any) -> ()): Connection
	local conn: any
	conn = Signal.Connect(self, function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal.Wait(self: any): ...any
	local thread = coroutine.running()
	Signal.Once(self, function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal.Fire(self: any, ...: any)
	for _, conn in table.clone(self._handlers) do
		if conn.Connected then
			task.spawn(conn._fn, ...)
		end
	end
end

function Signal.DisconnectAll(self: any)
	for _, conn in table.clone(self._handlers) do
		conn:Disconnect()
	end
end

return Signal
