--!strict
-- Point d'entrée serveur : crée les remotes, puis Init() de tous les services
-- dans l'ordre, puis Start() de tous les services. Chaque appel est isolé (xpcall) : une erreur
-- est signalée par warn et le service suivant démarre quand même.

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

-- Isolation des erreurs (Q12) : un Init ou un Start qui lève est signalé puis on passe au service
-- suivant. Sans cela, une erreur dans un service amont (ex. LeaderboardService.Start) empêchait
-- CongaService.Start de brancher le tick de 10 Hz : serveur ouvert, mais ni captures, ni coupes,
-- ni parades, ni instantanés. Le tick protège déjà chacun de ses appels aux autres services.
local function run(name: string, phase: string, fn: () -> ())
	local ok, err = xpcall(fn, debug.traceback)
	if not ok then
		warn(`[Server] {name} {phase}:`, err)
	end
end

local modules: { [string]: any } = {}
for _, name in ORDER do
	run(name, "require", function()
		modules[name] = require(Services:FindFirstChild(name) :: ModuleScript) :: any
	end)
end
for _, name in ORDER do
	local m = modules[name]
	if m and m.Init then
		run(name, "Init", m.Init)
	end
end
for _, name in ORDER do
	local m = modules[name]
	if m and m.Start then
		run(name, "Start", m.Start)
	end
end
