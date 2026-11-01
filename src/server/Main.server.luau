--!strict
-- Point d'entrée serveur : crée les remotes, puis Init() de tous les services dans l'ordre, puis
-- Start() de tous les services. Chaque appel est isolé (xpcall) : une erreur est signalée par warn
-- et le service suivant démarre quand même (leçon de Comet Conga : un Start en panne en amont
-- empêchait le tick de jeu de démarrer, serveur ouvert mais injouable).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)
Net.setup()

local Services = script.Parent.Services

-- Ordre explicite : un service n'appelle directement que ceux listés AVANT lui ; vers le haut, il
-- passe par Server/Signals. Les paquets du jeu ajoutent leurs services ici (une ligne chacun), le
-- service qui orchestre le tick de jeu en dernier.
local ORDER = {
	"DataService",
	"MonetizationService",
}

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
