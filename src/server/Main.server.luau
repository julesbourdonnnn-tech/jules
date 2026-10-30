--!strict
-- Point d'entrée serveur : crée les remotes, puis Init() de tous les services
-- dans l'ordre, puis Start() de tous les services.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)
Net.setup()

local Services = script.Parent.Services

-- Ordre explicite : un service ne dépend que de ceux listés avant lui.
local ORDER = {
	"DataService",
	"MonetizationService",
}

local modules = {}
for _, name in ORDER do
	modules[name] = require(Services:FindFirstChild(name) :: ModuleScript) :: any
end
for _, name in ORDER do
	if modules[name].Init then
		modules[name].Init()
	end
end
for _, name in ORDER do
	if modules[name].Start then
		modules[name].Start()
	end
end
