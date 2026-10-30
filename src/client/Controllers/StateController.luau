--!strict
-- Miroir client des données du joueur (lecture seule) alimenté par DataService.
--   State.get("coins")
--   State.observe("coins", function(value, old) ... end)  -- appelé tout de suite si prêt, puis à chaque changement
--   State.Changed:Connect(function(key, value, old) end)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)

local StateController = {}
StateController.Changed = Signal.new() :: Signal.Signal<string, any, any>
StateController.ReadySignal = Signal.new() :: Signal.Signal<>
StateController.ready = false

local data: { [string]: any } = {}

local function apply(key: string, value: any)
	local old = data[key]
	data[key] = value
	StateController.Changed:Fire(key, value, old)
end

function StateController.Init()
	Net.event("DataSnapshot").OnClientEvent:Connect(function(snapshot: { [string]: any })
		if type(snapshot) ~= "table" then
			return
		end
		local wasReady = StateController.ready
		for key, value in snapshot do
			apply(key, value)
		end
		for key in table.clone(data) do
			if snapshot[key] == nil then
				apply(key, nil)
			end
		end
		StateController.ready = true
		if not wasReady then
			StateController.ReadySignal:Fire()
		end
	end)

	Net.event("DataPatch").OnClientEvent:Connect(function(patch: { [string]: any }, removed: { string }?)
		if not StateController.ready or type(patch) ~= "table" then
			return
		end
		for key, value in patch do
			apply(key, value)
		end
		if type(removed) == "table" then
			for _, key in removed do
				apply(key, nil)
			end
		end
	end)
end

function StateController.Start()
	-- filet de sécurité : si l'instantané initial a été manqué, le redemander
	task.delay(4, function()
		if not StateController.ready then
			Net.event("RequestSnapshot"):FireServer()
		end
	end)
end

function StateController.get(key: string): any
	return data[key]
end

function StateController.waitReady(timeout: number?): boolean
	if StateController.ready then
		return true
	end
	local limit = timeout or 30
	local start = os.clock()
	while not StateController.ready and os.clock() - start < limit do
		task.wait(0.05)
	end
	return StateController.ready
end

-- Appelle fn(value, old) maintenant (si prêt) puis à chaque changement de `key`.
function StateController.observe(key: string, fn: (any, any) -> ()): Signal.Connection
	if StateController.ready then
		task.spawn(fn, data[key], nil)
	else
		StateController.ReadySignal:Once(function()
			fn(data[key], nil)
		end)
	end
	return StateController.Changed:Connect(function(changedKey: string, value: any, old: any)
		if changedKey == key then
			fn(value, old)
		end
	end)
end

return StateController
