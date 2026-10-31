--!strict
-- Point d'entrée serveur : crée les remotes, puis Init() de tous les services
-- dans l'ordre, puis Start() de tous les services.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)
Net.setup()

local Services = script.Parent.Services

-- Ordre explicite (GDD §12.3, docs/04-architecture.md §5) : un service n'appelle directement que
-- ceux listés avant lui ; vers le haut, il passe par Server/Signals. CongaService est le dernier :
-- il orchestre le tick de 10 Hz.
local ORDER = {
	"DataService",
	"MonetizationService",
	"WorldService",
	"NestService",
	"EconomyService",
	"AtlasService",
	"SpawnService",
	"EventService",
	"CrewService",
	"QuestService",
	"ProductService",
	"LeaderboardService",
	"CongaService",
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
